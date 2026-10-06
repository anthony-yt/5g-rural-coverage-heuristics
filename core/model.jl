# ==============================================================================
# PROYECTO: Optimización de Cobertura 5G Rural usando Heurísticas (UNMSM)
# MÓDULO: core/model.jl
# RESPONSABLES: Diego (Task 1.1: Grilla y Cobertura) & Jack (Task 1.2: Fitness)
# ==============================================================================

module Rural5GModel

export FRECUENCIA, P_MAX, P_MIN, UMBRAL_DBM, ALTURA_ANTENA, ALTURA_PERSONA, DZ
export N_ANTENAS, N_POBLACION
export antenas, poblacion
export hay_cobertura
export P_REQ_MATRIX, W_INTERF_MATRIX, I_MAX_MUTUA, I_MAX_SOLAP

# --- Parámetros Físicos y de Telecomunicaciones ---
const FRECUENCIA = 3500.0       # MHz (Banda 5G NR n78, 3GPP TS 38.104)
const P_MAX = 1.0               # Potencia máxima por antena en Watts
const P_MIN = 0.0               # Potencia mínima (antena apagada)
const UMBRAL_DBM = -80.0        # Sensibilidad mínima requerida para cobertura (dBm)
const ALTURA_ANTENA = 30.0      # Altura de la torre en metros
const ALTURA_PERSONA = 1.5      # Altura del usuario en metros
const DZ = (ALTURA_ANTENA - ALTURA_PERSONA) / 1000.0  # km (0.0285 km)

# Constante de pérdida base en espacio libre según recomendación UIT-R P.525-5:
# L(d) = 32.4 + 20*log10(f) + 20*log10(d)
const L_BASE_CONST = 32.4 + 20.0 * log10(FRECUENCIA) # 103.28136 dB

# --- Grillas Sintéticas del Escenario Rural ---
# 100 antenas en grilla 10x10 sobre terreno de 10x10 km (centradas cada 1 km)
const antenas = [(x, y) for x in 0.5:1.0:9.5 for y in 0.5:1.0:9.5]
const N_ANTENAS = length(antenas) # 100

# 2500 puntos de población separados cada 200 m (0.2 km)
const poblacion = [(x, y) for x in 0.1:0.2:9.9 for y in 0.1:0.2:9.9]
const N_POBLACION = length(poblacion) # 2500

# --- Función original de Diego (Task 1.1) ---
"""
    hay_cobertura(punto, antena, potencia) -> Bool

Evalúa si un punto de población recibe señal suficiente (>= -80 dBm)
desde una antena dada a una potencia dada (en Watts), según UIT-R P.525-5.
"""
function hay_cobertura(punto::Tuple{Float64, Float64}, antena::Tuple{Float64, Float64}, potencia::Float64)::Bool
    if potencia <= 0.0
        return false
    end

    dx = punto[1] - antena[1]
    dy = punto[2] - antena[2]
    distancia = sqrt(dx^2 + dy^2 + DZ^2)

    perdida = L_BASE_CONST + 20.0 * log10(distancia)
    potencia_dbm = 10.0 * log10(potencia) + 30.0
    senal_recibida = potencia_dbm - perdida

    return senal_recibida >= UMBRAL_DBM
end

# --- Estructuras Precomputadas de Alto Rendimiento (Jack - Task 1.2) ---
# Condición analítica:
# 10*log10(P) + 30 - (L_BASE_CONST + 20*log10(d)) >= UMBRAL_DBM
# 10*log10(P) >= UMBRAL_DBM - 30 + L_BASE_CONST + 20*log10(d)
# log10(P) >= (UMBRAL_DBM - 30 + L_BASE_CONST)/10 + 2*log10(d)
# P >= d^2 * 10^((UMBRAL_DBM - 30 + L_BASE_CONST)/10)
const K_POTENCIA = 10.0^((UMBRAL_DBM - 30.0 + L_BASE_CONST) / 10.0) # ≈ 0.2128867 W/km^2

function _precomputar_potencias_requeridas()
    mat = Matrix{Float64}(undef, N_POBLACION, N_ANTENAS)
    for (k, p) in enumerate(poblacion)
        for (i, a) in enumerate(antenas)
            d2 = (p[1] - a[1])^2 + (p[2] - a[2])^2 + DZ^2
            mat[k, i] = d2 * K_POTENCIA
        end
    end
    return mat
end

const P_REQ_MATRIX = _precomputar_potencias_requeridas()

# Matriz de pesos de interferencia entre antenas vecinas:
# Se penalizan pares de antenas con distancia <= 1.5 km (vecinos directos y diagonales)
# Peso inversamente proporcional al cuadrado de la distancia (1 / d^2)
function _precomputar_matriz_interferencia()
    W = zeros(Float64, N_ANTENAS, N_ANTENAS)
    for i in 1:N_ANTENAS
        ai = antenas[i]
        for j in (i+1):N_ANTENAS
            aj = antenas[j]
            d = sqrt((ai[1] - aj[1])^2 + (ai[2] - aj[2])^2)
            if d <= 1.5 # Vecinos directos (1.0 km) y diagonales (1.414 km)
                peso = 1.0 / (d^2)
                W[i, j] = peso
                W[j, i] = peso
            end
        end
    end
    return W
end

const W_INTERF_MATRIX = _precomputar_matriz_interferencia()

# Factores de normalización máximos (cuando todas las antenas están a P_MAX = 1.0)
const I_MAX_MUTUA = sum(W_INTERF_MATRIX) / 2.0 # Suma sobre i < j con P=1.0

function _calcular_max_solapamiento()
    solap = 0
    for k in 1:N_POBLACION
        count = 0
        for i in 1:N_ANTENAS
            if 1.0 >= P_REQ_MATRIX[k, i]
                count += 1
            end
        end
        if count > 1
            solap += (count - 1)
        end
    end
    return Float64(solap)
end

const I_MAX_SOLAP = _calcular_max_solapamiento()

end # module Rural5GModel
