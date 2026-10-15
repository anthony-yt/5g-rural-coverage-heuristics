# 5G Rural Coverage Heuristics 📡

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Optimización de asignación de potencias de transmisión en 100 antenas 5G para cobertura rural sintética utilizando **Algoritmo Genético (GA)** y **Recocido Simulado (SA)** en Julia.

**Proyecto Parcial — Modelos y Simulación**  
Facultad de Ingeniería de Sistemas e Informática — Universidad Nacional Mayor de San Marcos (UNMSM).

---

## 👥 Integrantes — Grupo 1

* **Anthony Josue Yucra Tintaya**
* **Jack Bryan Jimenes Trujillo**
* **Gael Stephan Carbajo Gallegos**
* **Diego Miranda**
* **Manuel Vera**
* **Yosue Cerdan**

---

## 🗂️ Estructura del Repositorio

```text
5g-rural-coverage-heuristics/
├── core/
│   ├── Grilla_y_Cobertura.ipynb  # Modelo base de propagación y pruebas de cobertura
│   ├── model.jl                  # Modelo físico UIT-R P.525-5, grillas y precomputación matricial
│   └── fitness.jl                # Función objetivo normalizada, cobertura e interferencia
├── heuristics/
│   ├── test_fitness.jl           # Batería de pruebas unitarias y benchmark de rendimiento
│   ├── run_pipeline.jl           # Pipeline de ejecución y auditoría para GA y SA
│   └── outputs/                  # Registro de resultados, curvas de convergencia y métricas CSV
├── analytics/                    # Visualizaciones espaciales 3D y análisis de sensibilidad
├── README.md                     # Documentación general del proyecto
└── requirements.txt              # Dependencias del entorno
```

---

## 📐 Modelo Físico y Matemático

### 1. Parámetros del Escenario Rural Sintético
* **Área de simulación**: Terreno plano de $10 \times 10\text{ km}$ ($100\text{ km}^2$).
* **Grilla de antenas (100 estaciones)**: Arreglo regular $10 \times 10$ con separación de $1\text{ km}$ ($x, y \in [0.5, 9.5]$).
* **Grilla de población (2500 puntos)**: Arreglo regular $50 \times 50$ con separación de $200\text{ m}$ ($x, y \in [0.1, 9.9]$).
* **Frecuencia portadora**: $f = 3500\text{ MHz}$ (Banda n78 de 5G NR).
* **Alturas**: Antena $h_{\text{ant}} = 30\text{ m}$, usuario $h_{\text{usr}} = 1.5\text{ m}$ ($\Delta z = 0.0285\text{ km}$).
* **Rango de potencia**: $P_i \in [0.0, 1.0]\text{ W}$ por antena ($P_i = 0\text{ W}$ equivale a estación apagada).
* **Umbral de cobertura**: Sensibilidad mínima $\gamma_{\text{th}} = -80.0\text{ dBm}$.

### 2. Modelo de Atenuación (UIT-R P.525-5)
La pérdida de trayectoria en espacio libre (FSPL) sigue la recomendación **UIT-R P.525-5 (ecuación 6)**:

$$L(d) = 32.4 + 20\log_{10}(f_{[\text{MHz}]}) + 20\log_{10}(d_{[\text{km}]})$$

La potencia recibida es $P_{rx} = 10\log_{10}(P_i) + 30 - L(d)$. Un punto de población está cubierto si $P_{rx} \ge -80\text{ dBm}$.

> **Aceleración Matricial**:  
> Despejando analíticamente la ecuación para $f = 3500\text{ MHz}$, la condición $P_{rx} \ge -80\text{ dBm}$ equivale a $P_i \ge d_{ki}^2 \cdot 0.2128867\text{ W}$. Precomputar esta matriz estática ($2500 \times 100$) reduce el tiempo de evaluación a **0.419 ms** ($\approx 2,387\text{ eval/s}$), evitando recalcular logaritmos y raíces en cada iteración de las metaheurísticas.

---

## ⚖️ Función Objetivo y Parámetro $\lambda$

$$\text{fitness}(\vec{P}) = \text{cobertura}_{\text{norm}}(\vec{P}) - \lambda \cdot \text{interferencia}_{\text{norm}}(\vec{P})$$

1. **Cobertura Poblacional ($\text{cobertura}_{\text{norm}} \in [0, 1]$)**: Fracción de los 2500 puntos cubiertos por al menos una antena activa.
2. **Interferencia Normalizada ($\text{interferencia}_{\text{norm}} \in [0, 1]$)**: Promedio ponderado ($50\% / 50\%$) normalizado respecto al caso de saturación máxima ($P_i = 1.0\text{ W}\ \forall i$):
   * **Interferencia mutua**: Entre antenas vecinas ($d_{ij} \le 1.5\text{ km}$), proporcional a $\frac{P_i \cdot P_j}{d_{ij}^2}$.
   * **Solapamiento en población**: Exceso de antenas servidoras simultáneas por punto habitado $\sum_{k} \max(0, N_{\text{serv}}(k) - 1)$.
3. **Comportamiento y Sensibilidad de $\lambda = 0.5$**:
   * **Sin penalización ($\lambda = 0.0$)**: No existe incentivo para apagar celdas redundantes, manteniendo las 100 antenas encendidas ($\approx 49.1\text{ W}$, interferencia $\approx 0.3614$).
   * **Con penalización activa ($\lambda = 0.5$)**: 
     * *Saturación trivial ($P_i = 1.0\text{ W}$)*: $100\%$ cobertura, interferencia $= 1.0000 \implies \text{fitness} = 0.5000$.
     * *Potencia uniforme regulada ($P_i = 0.35\text{ W}$)*: $100\%$ cobertura, interferencia $= 0.2346 \implies \text{fitness} = 0.8827$.
     * *Optimización heurística (GA / SA)*: Apaga $\sim 73$ antenas redundantes ($\approx 27$ activas y $\sim 9.6\text{ W}$ totales), logrando $100\%$ de cobertura e interferencia de $0.0078 \implies \text{fitness} \approx 0.9961$.
   * **Robustez del parámetro**: En el rango $\lambda \in [0.0625, 1.0]$ la cobertura se mantiene en $100\%$ con configuraciones equivalentes ($\sim 26\text{ a }27$ antenas). La cobertura recién disminuye significativamente para penalizaciones severas ($\lambda \ge 4$, cayendo a $99.72\%$, y $97.41\%$ con $\lambda = 16$).

---

## 🧪 Validación y Uso del Módulo Base

Resultados de validación de la función objetivo sobre vectores de control (`test_fitness.jl` con $\lambda = 0.5$):

| Escenario de Control | Cobertura (%) | Interferencia Norm. | Potencia Total (W) | Fitness |
|---|:---:|:---:|:---:|:---:|
| **1. Apagado total ($\vec{P} = \vec{0}$)** | 0.00% | 0.0000 | 0.00 W | **0.0000** |
| **2. Saturación trivial ($\vec{P} = \vec{1}$)** | 100.00% | 1.0000 | 100.00 W | **0.5000** |
| **3. Aleatorio ($\text{seed}=42$)** | 99.92% | 0.3870 | 51.06 W | **0.8057** |
| **4. Uniforme regulado ($P = 0.35\text{ W}$)** | 100.00% | 0.2346 | 35.00 W | **0.8827** |
| **5. Óptimo heurístico (SA / GA)** | 100.00% | 0.0078 | ~9.60 W | **0.9961** |

### Ejecución desde terminal

```bash
# Ejecutar pruebas unitarias y benchmark de la función objetivo
julia heuristics/test_fitness.jl

# Ejecutar pipeline completo de verificación (GA y SA)
julia heuristics/run_pipeline.jl
```

### Uso programático en Julia

```julia
include("core/fitness.jl")
using .Rural5GFitness

# Evaluación rápida para metaheurísticas (vector de 100 potencias en [0.0, 1.0])
fit = fitness(vector_potencias; lambda = 0.5)

# Reporte detallado de métricas para una solución
detalle = evaluar_solucion(vector_potencias)
println("Cobertura: ", detalle.cobertura_porcentaje, "%")
println("Interferencia: ", detalle.interferencia_norm)
println("Fitness: ", detalle.fitness)
```
