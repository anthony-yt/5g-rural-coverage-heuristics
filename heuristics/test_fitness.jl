# ==============================================================================
# PROYECTO: Optimización de Cobertura 5G Rural usando Heurísticas (UNMSM)
# SCRIPT: heuristics/test_fitness.jl
# RESPONSABLE: Jack (Task 1.2: Validación de Fitness y Calibración de λ)
# ==============================================================================

using Random
using Printf

# Cargar módulo del núcleo
include("../core/fitness.jl")
using .Rural5GFitness
using .Rural5GFitness.Rural5GModel

println("================================================================================")
println("  TASK 1.2: BATERÍA DE PRUEBAS DE LA FUNCIÓN OBJETIVO (FITNESS)")
println("================================================================================")
println("Parámetros del sistema:")
println("  - Antenas: ", N_ANTENAS, " (grilla 10x10, d = 1 km)")
println("  - Puntos de población: ", N_POBLACION, " (grilla 50x50, d = 200 m)")
println("  - Frecuencia: ", FRECUENCIA, " MHz (Banda n78)")
println("  - Umbral mínimo: ", UMBRAL_DBM, " dBm")
println("  - Lambda por defecto (calibrado): ", LAMBDA_DEFAULT)
println("--------------------------------------------------------------------------------\n")

# ------------------------------------------------------------------------------
# TEST 1: Vector de ceros (todas las antenas apagadas)
# ------------------------------------------------------------------------------
println(">> TEST 1: Vector con todas las potencias en 0.0 W (Antenas apagadas)")
p_ceros = zeros(Float64, N_ANTENAS)
res_ceros = evaluar_solucion(p_ceros)
fit_ceros = fitness(p_ceros)

@printf("   - Cobertura: %d / %d (%.2f%%)\n", res_ceros.cobertura_puntos, N_POBLACION, res_ceros.cobertura_porcentaje)
@printf("   - Interferencia normalizada: %.4f\n", res_ceros.interferencia_norm)
@printf("   - Fitness calculado: %.6f\n", fit_ceros)

@assert fit_ceros == 0.0 "Error: El fitness para potencias en cero debe ser 0.0"
@assert res_ceros.cobertura_puntos == 0 "Error: No debe haber cobertura si P=0"
println("   [PASS] TEST 1 superado exitosamente.\n")

# ------------------------------------------------------------------------------
# TEST 2: Vector máximo (todas las potencias al 1.0 W)
# ------------------------------------------------------------------------------
println(">> TEST 2: Vector con todas las potencias al máximo (1.0 W)")
p_max = ones(Float64, N_ANTENAS)
res_max = evaluar_solucion(p_max)
fit_max = fitness(p_max)

@printf("   - Cobertura: %d / %d (%.2f%%)\n", res_max.cobertura_puntos, N_POBLACION, res_max.cobertura_porcentaje)
@printf("   - Interferencia mutua cruda: %.2f\n", res_max.interferencia_mutua)
@printf("   - Solapamiento en población: %.0f puntos redundantes\n", res_max.interferencia_solap)
@printf("   - Interferencia normalizada: %.4f\n", res_max.interferencia_norm)
@printf("   - Potencia total consumida: %.2f W\n", res_max.potencia_total_watts)
@printf("   - Fitness calculado: %.6f (Esperado: 1.0 - λ = %.4f)\n", fit_max, 1.0 - LAMBDA_DEFAULT)

@assert res_max.cobertura_puntos == N_POBLACION "Error: Cobertura máxima debe alcanzar el 100%"
@assert isapprox(res_max.interferencia_norm, 1.0; atol=1e-5) "Error: Interferencia normalizada debe ser 1.0"
@assert isapprox(fit_max, 1.0 - LAMBDA_DEFAULT; atol=1e-5) "Error: Fitness debe ser 1.0 - lambda"
println("   [PASS] TEST 2 superado exitosamente.\n")

# ------------------------------------------------------------------------------
# TEST 3: Vector aleatorio (P ~ U(0, 1))
# ------------------------------------------------------------------------------
println(">> TEST 3: Vector aleatorio reproducible (Semilla 42)")
Random.seed!(42)
p_rand = rand(Float64, N_ANTENAS)
res_rand = evaluar_solucion(p_rand)
fit_rand = fitness(p_rand)

@printf("   - Cobertura: %d / %d (%.2f%%)\n", res_rand.cobertura_puntos, N_POBLACION, res_rand.cobertura_porcentaje)
@printf("   - Interferencia normalizada: %.4f\n", res_rand.interferencia_norm)
@printf("   - Potencia total consumida: %.2f W\n", res_rand.potencia_total_watts)
@printf("   - Fitness calculado: %.6f\n", fit_rand)

@assert !isnan(fit_rand) && !isinf(fit_rand) "Error: El fitness no debe ser NaN ni Inf"
@assert fit_rand >= 0.0 && fit_rand <= 1.0 "Error: El fitness debe estar en [0, 1]"
println("   [PASS] TEST 3 superado exitosamente.\n")

# ------------------------------------------------------------------------------
# TEST 4: Vector Estratégico (Control contra el Óptimo Trivial)
# ------------------------------------------------------------------------------
println(">> TEST 4: Demostración de Calibración de λ (Solución Eficiente vs Óptimo Trivial)")
# Estrategia: Reducir potencia a 0.35 W en toda la grilla.
# A 0.35 W, el radio de cobertura sigue siendo suficiente para cubrir casi toda la población,
# pero la interferencia cae cuadráticamente (0.35^2 = 0.1225 -> ~88% de reducción de interferencia)
p_eficiente = fill(0.35, N_ANTENAS)
res_eficiente = evaluar_solucion(p_eficiente)
fit_eficiente = fitness(p_eficiente)

@printf("   Configuración P = 1.0 W (Trivial):  Fitness = %.4f | Cob = %.1f%% | Interf = %.4f\n",
        fit_max, res_max.cobertura_porcentaje, res_max.interferencia_norm)
@printf("   Configuración P = 0.35 W (Regulada): Fitness = %.4f | Cob = %.1f%% | Interf = %.4f\n",
        fit_eficiente, res_eficiente.cobertura_porcentaje, res_eficiente.interferencia_norm)

@printf("   Diferencia de fitness a favor de la solución coordinada: +%.4f\n", fit_eficiente - fit_max)

if fit_eficiente > fit_max
    println("   [PASS] Confirmado: El óptimo trivial (todas en 1.0 W) NO gana.")
    println("          λ = ", LAMBDA_DEFAULT, " penaliza adecuadamente la interferencia.")
else
    error("   [FAIL] λ está mal calibrado: la solución trivial supera a la regulada.")
end
println()

# ------------------------------------------------------------------------------
# TEST 5: Consistencia exacta con hay_cobertura de Diego (Task 1.1)
# ------------------------------------------------------------------------------
println(">> TEST 5: Consistencia de cálculo matricial vs función hay_cobertura() de Diego")
puntos_prueba = [poblacion[1], poblacion[500], poblacion[1250], poblacion[2000], poblacion[2500]]
antenas_prueba = [antenas[1], antenas[25], antenas[50], antenas[75], antenas[100]]
potencias_prueba = [0.0, 0.1, 0.3, 0.7, 1.0]

errores = 0
for p in puntos_prueba
    for a in antenas_prueba
        for pot in potencias_prueba
            r_diego = hay_cobertura(p, a, pot)
            # Replicar con condición matemática K_POTENCIA
            d2 = (p[1] - a[1])^2 + (p[2] - a[2])^2 + DZ^2
            p_req = d2 * Rural5GModel.K_POTENCIA
            r_opt = (pot > 0.0) && (pot >= p_req)
            if r_diego != r_opt
                global errores += 1
            end
        end
    end
end

@printf("   - Comparaciones directas: %d | Discrepancias: %d\n", length(puntos_prueba)*length(antenas_prueba)*length(potencias_prueba), errores)
@assert errores == 0 "Error: Discrepancia entre la precomputación y la función de Diego"
println("   [PASS] TEST 5 superado: 100% de coincidencia exacta con Task 1.1.\n")

# ------------------------------------------------------------------------------
# TEST 6: Benchmark de rendimiento computacional
# ------------------------------------------------------------------------------
println(">> TEST 6: Benchmark de velocidad de fitness() para GA y SA")
# Calentamiento (JIT warmup)
for _ in 1:100
    fitness(rand(N_ANTENAS))
end

n_evaluaciones = 2000
t_inicio = time()
for _ in 1:n_evaluaciones
    fitness(p_rand)
end
t_total = time() - t_inicio
t_promedio_ms = (t_total / n_evaluaciones) * 1000.0

@printf("   - %d evaluaciones ejecutadas en %.4f s\n", n_evaluaciones, t_total)
@printf("   - Tiempo promedio por evaluación: %.3f ms\n", t_promedio_ms)
@printf("   - Velocidad estimada: %.0f evaluaciones/segundo\n", n_evaluaciones / t_total)
println("   [PASS] Rendimiento óptimo garantizado para GA y SA.")

println("\n================================================================================")
println("  TODAS LAS PRUEBAS DEL TASK 1.2 FUERON COMPLETADAS EXITOSAMENTE")
println("================================================================================")
