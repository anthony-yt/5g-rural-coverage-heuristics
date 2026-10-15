# Función objetivo (fitness) y métricas de cobertura e interferencia

module Rural5GFitness

include("model.jl")
using .Rural5GModel

export fitness, evaluar_cobertura, evaluar_interferencia, evaluar_solucion
export LAMBDA_DEFAULT

# Factor de penalización por interferencia
const LAMBDA_DEFAULT = 0.5

# Estructura con el resumen de la evaluación
struct EvaluacionResultado
    fitness::Float64
    cobertura_puntos::Int
    cobertura_norm::Float64
    cobertura_porcentaje::Float64
    interferencia_mutua::Float64
    interferencia_solap::Float64
    interferencia_norm::Float64
    potencia_total_watts::Float64
end

# Calcula la cobertura poblacional
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

# Calcula la interferencia mutua y solapamiento
function evaluar_interferencia(potencias::Vector{Float64}, servidoras::Vector{Int})
    # 1. Interferencia entre antenas vecinas
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

    # 2. Solapamiento en puntos de población
    solap = 0
    @inbounds for k in 1:N_POBLACION
        s = servidoras[k]
        if s > 1
            solap += (s - 1)
        end
    end
    i_solap_norm = I_MAX_SOLAP > 0.0 ? clamp(Float64(solap) / I_MAX_SOLAP, 0.0, 1.0) : 0.0

    # Métrica combinada
    i_combinada_norm = 0.5 * i_mutua_norm + 0.5 * i_solap_norm

    return i_mutua, Float64(solap), i_combinada_norm
end

# Evaluación completa de la solución
function evaluar_solucion(potencias::Vector{Float64}; lambda::Float64 = LAMBDA_DEFAULT)::EvaluacionResultado
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

# Función objetivo para GA y SA: Cobertura - λ * Interferencia
function fitness(potencias::Vector{Float64}; lambda::Float64 = LAMBDA_DEFAULT)::Float64
    @assert length(potencias) == N_ANTENAS "El vector debe tener exactamente 100 potencias"

    puntos_cubiertos = 0
    solap = 0

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
