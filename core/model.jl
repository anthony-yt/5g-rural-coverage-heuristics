# Modelo de propagación y grilla rural 5G

module Rural5GModel

export FRECUENCIA, P_MAX, P_MIN, UMBRAL_DBM, ALTURA_ANTENA, ALTURA_PERSONA, DZ
export N_ANTENAS, N_POBLACION
export antenas, poblacion
export hay_cobertura
export P_REQ_MATRIX, W_INTERF_MATRIX, I_MAX_MUTUA, I_MAX_SOLAP

# Parámetros del sistema y propagación
const FRECUENCIA = 3500.0       # MHz (Banda n78)
const P_MAX = 1.0               # Potencia máxima en Watts
const P_MIN = 0.0               # Potencia mínima (apagada)
const UMBRAL_DBM = -80.0        # Señal mínima para cobertura (dBm)
const ALTURA_ANTENA = 30.0      # Metros
const ALTURA_PERSONA = 1.5      # Metros
const DZ = (ALTURA_ANTENA - ALTURA_PERSONA) / 1000.0  # km

# Pérdida base (UIT-R P.525-5)
const L_BASE_CONST = 32.4 + 20.0 * log10(FRECUENCIA)

# Grilla de 100 antenas y 2500 puntos de población
const antenas = [(x, y) for x in 0.5:1.0:9.5 for y in 0.5:1.0:9.5]
const N_ANTENAS = length(antenas)

const poblacion = [(x, y) for x in 0.1:0.2:9.9 for y in 0.1:0.2:9.9]
const N_POBLACION = length(poblacion)

# Evalúa si un punto recibe señal suficiente (>= -80 dBm)
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

# Precomputar potencia requerida para cobertura
const K_POTENCIA = 10.0^((UMBRAL_DBM - 30.0 + L_BASE_CONST) / 10.0)

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

# Matriz de interferencia entre antenas vecinas (distancia <= 1.5 km)
function _precomputar_matriz_interferencia()
    W = zeros(Float64, N_ANTENAS, N_ANTENAS)
    for i in 1:N_ANTENAS
        ai = antenas[i]
        for j in (i+1):N_ANTENAS
            aj = antenas[j]
            d = sqrt((ai[1] - aj[1])^2 + (ai[2] - aj[2])^2)
            if d <= 1.5
                peso = 1.0 / (d^2)
                W[i, j] = peso
                W[j, i] = peso
            end
        end
    end
    return W
end

const W_INTERF_MATRIX = _precomputar_matriz_interferencia()

# Normalizaciones de interferencia máxima
const I_MAX_MUTUA = sum(W_INTERF_MATRIX) / 2.0

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
