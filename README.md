# 5G Rural Coverage Heuristics 📡

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org/)
[![Status](https://img.shields.io/badge/Sprint-Frente%201%20Completado-success)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Optimización de asignación de potencias de transmisión en 100 antenas 5G para cobertura rural sintética utilizando **Algoritmo Genético (GA)** y **Recocido Simulado (SA)** en Julia.

Proyecto Parcial — *Modelos y Simulación*, Universidad Nacional Mayor de San Marcos (UNMSM).

---

## 🗂️ Estructura del Repositorio

```text
5g-rural-coverage-heuristics/
├── core/
│   ├── Grilla_y_Cobertura.ipynb  # Notebook interactivo (Task 1.1 + Task 1.2)
│   ├── model.jl                  # Modelo físico UIT-R P.525-5, grillas y precomputación matricial
│   └── fitness.jl                # Función objetivo normalizada, cobertura e interferencia
├── heuristics/
│   ├── test_fitness.jl           # Batería de pruebas unitarias, extremos y benchmark
│   ├── run_pipeline.jl           # Runner de integración E2E para GA y SA (Task 1.3)
│   └── outputs/                  # Registro de resultados, curvas de convergencia y métricas
├── analytics/                    # Visualizaciones interactivas 3D y análisis comparativos
├── README.md                     # Documentación técnica y guía de integración
└── requirements.txt              # Requerimientos y dependencias
```

---

## 🎯 Estado del Sprint: Frente 1 (La Función Objetivo)

| Tarea | Responsable | Estado | Entregable / Resultado |
|---|---|:---:|---|
| **Task 1.1: Grilla y Modelo de Atenuación** | Diego | ✅ Completado | Terreno 10×10 km, 100 antenas, 2500 hab., modelo UIT-R P.525-5, `hay_cobertura`. |
| **Task 1.2: Implementación de `fitness()` y $\lambda$** | Jack | ✅ Completado | Función `fitness(P)`, modelo de interferencia normalizado, calibración $\lambda = 0.5$ y tests. |
| **Task 1.3: Pipeline de Verificación E2E** | Jack | ✅ Preparado | `run_pipeline.jl` listo con protocolo de validación independiente para GA y SA. |

---

## 📐 Modelo Físico y Matemático

### 1. Parámetros del Escenario Rural Sintético
* **Área de simulación**: Terreno rural plano de $10 \times 10\text{ km}$ ($100\text{ km}^2$).
* **Grilla de antenas (100 antenas)**: Arreglo regular $10 \times 10$ centrado con separación de $1\text{ km}$ ($x, y \in [0.5, 9.5]$ con paso $1.0\text{ km}$).
* **Grilla de población (2500 puntos)**: Arreglo regular $50 \times 50$ con separación de $200\text{ m}$ ($x, y \in [0.1, 9.9]$ con paso $0.2\text{ km}$).
* **Frecuencia portadora**: $f = 3500\text{ MHz}$ (Banda n78 de 5G NR, estándar 3GPP TS 38.104 / ETSI).
* **Alturas de propagación**: Altura de antena $h_{\text{ant}} = 30\text{ m}$, altura de usuario $h_{\text{usr}} = 1.5\text{ m}$ ($\Delta z = 0.0285\text{ km}$).
* **Rango de potencia**: $P_i \in [0.0, 1.0]\text{ W}$ por antena. Si $P_i = 0$, la antena se considera apagada.
* **Umbral de sensibilidad**: $\gamma_{\text{th}} = -80.0\text{ dBm}$.

### 2. Modelo de Atenuación (UIT-R P.525-5)
La pérdida de trayectoria en espacio libre (FSPL) se calcula según la recomendación formal **UIT-R P.525-5 (2024), ecuación 6**:
$$L(d) = 32.4 + 20\log_{10}(f_{[\text{MHz}]}) + 20\log_{10}(d_{[\text{km}]})$$
Para $f = 3500\text{ MHz}$, la pérdida base es:
$$L(d) = 103.28136 + 20\log_{10}(d)$$
La potencia recibida en el receptor es $P_{rx} = P_{\text{tx, dBm}} - L(d) = 10\log_{10}(P_i) + 30 - L(d)$. Un punto recibe cobertura si $P_{rx} \ge -80\text{ dBm}$.

> **Optimización Analítica de Alto Rendimiento (Jack)**:  
> La condición de cobertura equivale exactamente a $P_i \ge d_{ki}^2 \cdot 0.2128867$. Al precomputar esta matriz estática ($2500 \times 100$), cada evaluación de cobertura toma menos de **0.4 ms** en Julia (más de 2,300 evaluaciones/segundo), evitando re-evaluar logaritmos y raíces en cada generación de los algoritmos.

---

## ⚖️ Función Objetivo y Calibración de $\lambda$ (Task 1.2)

$$\text{fitness}(\vec{P}) = \text{cobertura}_{\text{norm}}(\vec{P}) - \lambda \cdot \text{interferencia}_{\text{norm}}(\vec{P})$$

### Componentes:
1. **Cobertura Poblacional ($\text{cobertura}_{\text{norm}}$)**:
   Fracción de los 2500 puntos de población cubiertos por al menos una antena activa:
   $$\text{cobertura}_{\text{norm}}(\vec{P}) = \frac{1}{2500} \sum_{k=1}^{2500} \mathbb{I}(N_{\text{servidoras}}(k) \ge 1) \in [0.0, 1.0]$$

2. **Interferencia Normalizada ($\text{interferencia}_{\text{norm}}$)**:
   Modela dos fenómenos reales de degradación:
   * **Interferencia mutua entre antenas vecinas ($I_{\text{mutua}}$)**: Pares de antenas contiguas a distancia $d_{ij} \le 1.5\text{ km}$ (adyacentes y diagonales), penalizadas proporcionalmente a $\frac{P_i \cdot P_j}{d_{ij}^2}$.
   * **Solapamiento redundante en población ($I_{\text{solap}}$)**: Acumulación de señales competidoras $\sum_{k} \max(0, N_{\text{servidoras}}(k) - 1)$.
   * Ambas componentes se combinan equilibradamente ($50\% / 50\%$) y se normalizan respecto al caso de saturación máxima ($P_i = 1.0\ \forall i$).

3. **Justificación y Calibración del Parámetro $\lambda = 0.5$**:
   * Si $\lambda < 0.08$: El óptimo trivial de transmitir todas las antenas a potencia máxima ($P_i = 1.0$) siempre ganaría, desincentivando cualquier optimización.
   * Si $\lambda = 0.5$:
     * Solución trivial ($P_i = 1.0\ \forall i$): Cobertura = $100\%$, Interferencia = $1.0 \implies \mathbf{fitness = 0.5000}$.
     * Solución regulada/coordinada ($P_i = 0.35\ \forall i$): Cobertura = $100\%$, Interferencia = $0.2346 \implies \mathbf{fitness = 0.8827}$.
     * **Margen de ganancia para la heurística**: $+0.3827$ sobre la solución trivial. Esto garantiza que GA y SA tengan un gradiente de búsqueda efectivo para encontrar patrones coordinados.
   * Si $\lambda > 0.9$: Se penalizaría tanto la interferencia que las heurísticas preferirían apagar antenas y sacrificar cobertura rural.

---

## 🧪 Batería de Pruebas Unitarias (Resultados Verificados)

Ejecutados con `julia heuristics/test_fitness.jl`:

| Vector de Prueba | Cobertura Hab. | Cobertura % | Interferencia Norm. | Potencia Total (W) | Fitness | Resultado / Observación |
|---|:---:|:---:|:---:|:---:|:---:|---|
| **1. Ceros ($\vec{P} = \vec{0}$)** | 0 / 2500 | 0.00% | 0.0000 | 0.00 W | **0.0000** | Antenas apagadas, sin cobertura ni interferencia. |
| **2. Máximo ($\vec{P} = \vec{1}$)** | 2500 / 2500 | 100.00% | 1.0000 | 100.00 W | **0.5000** | Óptimo trivial penalizado por saturación. |
| **3. Aleatorio ($\text{seed}=42$)** | 2498 / 2500 | 99.92% | 0.3870 | 51.06 W | **0.8057** | Valores continuos válidos sin anomalías. |
| **4. Control ($P = 0.35\text{ W}$)** | 2500 / 2500 | 100.00% | 0.2346 | 35.00 W | **0.8827** | **Supera al trivial por +0.3827 puntos.** |

* **Coincidencia con Task 1.1**: 125 pruebas cruzadas contra `hay_cobertura` de Diego $\to$ **0 discrepancias (100% consistencia)**.
* **Velocidad de cómputo**: **0.419 ms** por evaluación ($\approx 2,387$ evaluaciones/segundo).

---

## 🚀 Guía de Integración para el Equipo

### Para Gael (Task 2.1 - Algoritmo Genético) y Manuel (Task 2.2 - Recocido Simulado):
Importar la función objetivo en sus scripts:
```julia
include("../core/fitness.jl")
using .Rural5GFitness

# Evaluar fitness rápidamente en el bucle principal:
fit = fitness(cromosoma_potencias) # Vector{Float64} de longitud 100, valores en [0.0, 1.0]

# Obtener métricas detalladas para la mejor solución final:
detalle = evaluar_solucion(mejor_vector)
println("Cobertura: ", detalle.cobertura_porcentaje, "%")
println("Interferencia: ", detalle.interferencia_norm)
println("Fitness: ", detalle.fitness)
```

### Para Anthony (Task 3.3 - Análisis de Sensibilidad de $\lambda$):
Puede evaluar cómo varía el óptimo modificando el parámetro de palabra clave `lambda`:
```julia
fit_mitad = fitness(potencias; lambda = 0.25) # Menor penalización
fit_base  = fitness(potencias; lambda = 0.50) # Calibrado central
fit_doble = fitness(potencias; lambda = 1.00) # Alta penalización
```

### Para Yosue (Task 3.1 - Visualización 3D y Convergencia):
Los arrays de posiciones estáticas están exportados en `Rural5GModel`:
```julia
using .Rural5GFitness.Rural5GModel
# antenas: Vector de 100 Tuplas (x, y)
# poblacion: Vector de 2500 Tuplas (x, y)
```

---

## 🛠️ Cómo Ejecutar las Pruebas

Para reproducir las pruebas del Task 1.2:
```bash
julia heuristics/test_fitness.jl
```

Para verificar el runner del pipeline E2E (Task 1.3):
```bash
julia heuristics/run_pipeline.jl
```
