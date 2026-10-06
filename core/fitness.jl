# ==============================================================================
# PROYECTO: Optimización de Cobertura 5G Rural usando Heurísticas (UNMSM)
# MÓDULO: core/fitness.jl
# RESPONSABLE: Jack (Task 1.2: Implementar fitness y calibrar λ)
# ==============================================================================

module Rural5GFitness

include("model.jl")
using .Rural5GModel

export fitness, evaluar_cobertura, evaluar_interferencia, evaluar_solucion
export LAMBDA_DEFAULT

"""
    LAMBDA_DEFAULT = 0.5

Valor calibrado de penalización de interferencia.
Justificación:
- Con λ < 0.08, el óptimo trivial (todas las antenas al 100%) predomina.
- Con λ = 0.5, el óptimo trivial obtiene fitness = 1.0 - 0.5 = 0.50,
  mientras que una distribución coordinada (cobertura ~95%, interferencia ~25%)
  alcanza fitness ≈ 0.825, premiando el ahorro energético y la mitigación de solapamiento.
- Con λ > 0.9, se sacrifica cobertura excesiva para minimizar interferencia.
"""
const LAMBDA_DEFAULT = 0.5

# Estructura para almacenar el desglose completo de una evaluación
struct EvaluacionResultado
    fitness::Float64
    cobertura_puntos::Int           # 0 a 2500 puntos
    cobertura_norm::Float64         # 0.0 a 1.0
    cobertura_porcentaje::Float64   # 0.0% a 100.0%
    interferencia_mutua::Float64    # Valor cuadrático entre antenas vecinas
    interferencia_solap::Float64    # Cantidad de solapamientos en población
    interferencia_norm::Float64     # 0.0 a 1.0 (métrica combinada)
    potencia_total_watts::Float64   # Suma de potencias (eficiencia energética)
end

"""
    evaluar_cobertura(potencias::Vector{Float64}) -> (Int, Float64, Vector{Int})

Calcula la cobertura poblacional dada la configuración de potencias (W).
Retorna:
- `puntos_cubiertos`: Número de puntos de población con señal >= -80 dBm.
- `fraccion_cubierta`: Cobertura normalizada [0.0, 1.0].
- `servidoras_por_punto`: Vector con el número de antenas que cubren cada punto k.
"""
function evaluar_cobertura(potencias::Vector{Float64})
    @assert length(potencias) == N_ANTENAS "El vector de potencias debe tener 100 elementos"
    
    puntos_cubiertos = 0
    servidoras = zeros(Int, N_POBLACION)

    @inbounds for k in 1:N_POBLACION
        count = 0
        for i in 1:N_ANTENAS
            p = potencias[i]
            if p > 0.0 && p >= P_REQ_MATRIX[k, i]
                count += 1
            end
        end
        servidoras[k] = count
        if count > 0
            puntos_cubiertos += 1
        end
    end

    fraccion = puntos_cubiertos / Float64(N_POBLACION)
    return puntos_cubiertos, fraccion, servidoras
end

"""
    evaluar_interferencia(potencias::Vector{Float64}, servidoras::Vector{Int}) -> (Float64, Float64, Float64)

Calcula la interferencia en dos frentes complementarios:
1. `I_mutua`: Interferencia directa entre antenas vecinas (d <= 1.5 km), ponderada por Pi * Pj / d^2.
2. `I_solap`: Solapamiento redundante en puntos de población (sum max(0, N_servidoras - 1)).
3. `I_norm`: Métrica combinada normalizada en [0.0, 1.0].
"""
function evaluar_interferencia(potencias::Vector{Float64}, servidoras::Vector{Int})
    # 1. Interferencia cruzada entre antenas vecinas
    i_mutua = 0.0
    @inbounds for i in 1:N_ANTENAS
        pi = potencias[i]
        if pi > 0.0
            for j in (i+1):N_ANTENAS
                pj = potencias[j]
                if pj > 0.0 && W_INTERF_MATRIX[i, j] > 0.0
                    i_mutua += W_INTERF_MATRIX[i, j] * pi * pj
                end
            end
        end
    end
    i_mutua_norm = I_MAX_MUTUA > 0.0 ? clamp(i_mutua / I_MAX_MUTUA, 0.0, 1.0) : 0.0

    # 2. Solapamiento redundante en los puntos de población
    solap = 0
    @inbounds for k in 1:N_POBLACION
        s = servidoras[k]
        if s > 1
            solap += (s - 1)
        end
    end
    i_solap_norm = I_MAX_SOLAP > 0.0 ? clamp(Float64(solap) / I_MAX_SOLAP, 0.0, 1.0) : 0.0

    # Métrica combinada balanceada (50% interacción física de antenas, 50% impacto en población)
    i_combinada_norm = 0.5 * i_mutua_norm + 0.5 * i_solap_norm

    return i_mutua, Float64(solap), i_combinada_norm
end

"""
    evaluar_solucion(potencias::Vector{Float64}; lambda::Float64 = LAMBDA_DEFAULT) -> EvaluacionResultado

Realiza una evaluación completa y detallada de la solución, retornando un `EvaluacionResultado`.
"""
function evaluar_solucion(potencias::Vector{Float64}; lambda::Float64 = LAMBDA_DEFAULT)::EvaluacionResultado
    # Reparación / clamping preventivo dentro del rango físico [0, P_MAX]
    p_clamped = clamp.(potencias, P_MIN, P_MAX)

    pts_cubiertos, cob_norm, serv = evaluar_cobertura(p_clamped)
    i_mut, i_sol, i_norm = evaluar_interferencia(p_clamped, serv)

    fit = cob_norm - lambda * i_norm
    p_total = sum(p_clamped)

    return EvaluacionResultado(
        fit,
        pts_cubiertos,
        cob_norm,
        cob_norm * 100.0,
        i_mut,
        i_sol,
        i_norm,
        p_total
    )
end

"""
    fitness(potencias::Vector{Float64}; lambda::Float64 = LAMBDA_DEFAULT) -> Float64

Función objetivo optimizada para ser llamada por el Algoritmo Genético (GA)
y Recocido Simulado (SA).

Objetivo: Maximizar cobertura poblacional minimizando interferencia por solapamiento.
    fitness(P) = Cobertura_norm(P) - λ * Interferencia_norm(P)
"""
function fitness(potencias::Vector{Float64}; lambda::Float64 = LAMBDA_DEFAULT)::Float64
    @assert length(potencias) == N_ANTENAS "El vector debe tener exactamente 100 potencias"

    puntos_cubiertos = 0
    solap = 0

    # Cobertura y solapamiento en una sola pasada de alto rendimiento
    @inbounds for k in 1:N_POBLACION
        count = 0
        for i in 1:N_ANTENAS
            p = potencias[i]
            if p > 0.0 && p >= P_REQ_MATRIX[k, i]
                count += 1
            end
        end
        if count > 0
            puntos_cubiertos += 1
            if count > 1
                solap += (count - 1)
            end
        end
    end

    cob_norm = puntos_cubiertos / Float64(N_POBLACION)

    # Interferencia mutua entre antenas
    i_mutua = 0.0
    @inbounds for i in 1:N_ANTENAS
        pi = potencias[i]
        if pi > 0.0
            for j in (i+1):N_ANTENAS
                pj = potencias[j]
                if pj > 0.0 && W_INTERF_MATRIX[i, j] > 0.0
                    i_mutua += W_INTERF_MATRIX[i, j] * pi * pj
                end
            end
        end
    end

    i_mutua_norm = i_mutua / I_MAX_MUTUA
    i_solap_norm = Float64(solap) / I_MAX_SOLAP
    i_norm = 0.5 * i_mutua_norm + 0.5 * i_solap_norm

    return cob_norm - lambda * i_norm
end

end # module Rural5GFitness
