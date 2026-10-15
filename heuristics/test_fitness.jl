# Pruebas de la función objetivo (fitness)

using Random
using Printf

include("../core/fitness.jl")
using .Rural5GFitness
using .Rural5GFitness.Rural5GModel

println("=== Pruebas de la función objetivo (fitness) ===")
println("Antenas: ", N_ANTENAS, " | Puntos de población: ", N_POBLACION)
println("Frecuencia: ", FRECUENCIA, " MHz | Umbral: ", UMBRAL_DBM, " dBm | Lambda: ", LAMBDA_DEFAULT)
println()

# 1. Antenas apagadas (P = 0)
println(">> Prueba 1: Antenas apagadas (0.0 W)")
p_ceros = zeros(Float64, N_ANTENAS)
res_ceros = evaluar_solucion(p_ceros)
fit_ceros = fitness(p_ceros)

@printf("   - Cobertura: %d / %d (%.2f%%)\n", res_ceros.cobertura_puntos, N_POBLACION, res_ceros.cobertura_porcentaje)
@printf("   - Interferencia: %.4f\n", res_ceros.interferencia_norm)
@printf("   - Fitness: %.6f\n", fit_ceros)

@assert fit_ceros == 0.0 "Error: El fitness para potencias en cero debe ser 0.0"
@assert res_ceros.cobertura_puntos == 0 "Error: No debe haber cobertura si P=0"
println("   OK\n")

# 2. Potencia máxima (P = 1.0 W)
println(">> Prueba 2: Todas las antenas a potencia máxima (1.0 W)")
p_max = ones(Float64, N_ANTENAS)
res_max = evaluar_solucion(p_max)
fit_max = fitness(p_max)

@printf("   - Cobertura: %d / %d (%.2f%%)\n", res_max.cobertura_puntos, N_POBLACION, res_max.cobertura_porcentaje)
@printf("   - Interferencia mutua: %.2f\n", res_max.interferencia_mutua)
@printf("   - Solapamiento: %.0f puntos\n", res_max.interferencia_solap)
@printf("   - Interferencia normalizada: %.4f\n", res_max.interferencia_norm)
@printf("   - Potencia total: %.2f W\n", res_max.potencia_total_watts)
@printf("   - Fitness: %.6f (Esperado: %.4f)\n", fit_max, 1.0 - LAMBDA_DEFAULT)

@assert res_max.cobertura_puntos == N_POBLACION "Error: Cobertura máxima debe alcanzar el 100%"
@assert isapprox(res_max.interferencia_norm, 1.0; atol=1e-5) "Error: Interferencia normalizada debe ser 1.0"
@assert isapprox(fit_max, 1.0 - LAMBDA_DEFAULT; atol=1e-5) "Error: Fitness debe ser 1.0 - lambda"
println("   OK\n")

# 3. Potencias aleatorias
println(">> Prueba 3: Potencias aleatorias (semilla 42)")
Random.seed!(42)
p_rand = rand(Float64, N_ANTENAS)
res_rand = evaluar_solucion(p_rand)
fit_rand = fitness(p_rand)

@printf("   - Cobertura: %d / %d (%.2f%%)\n", res_rand.cobertura_puntos, N_POBLACION, res_rand.cobertura_porcentaje)
@printf("   - Interferencia normalizada: %.4f\n", res_rand.interferencia_norm)
@printf("   - Potencia total: %.2f W\n", res_rand.potencia_total_watts)
@printf("   - Fitness: %.6f\n", fit_rand)

@assert !isnan(fit_rand) && !isinf(fit_rand) "Error: El fitness no debe ser NaN ni Inf"
@assert fit_rand >= 0.0 && fit_rand <= 1.0 "Error: El fitness debe estar en [0, 1]"
println("   OK\n")

# 4. Potencia moderada (P = 0.35 W)
println(">> Prueba 4: Potencia moderada vs potencia máxima")
p_eficiente = fill(0.35, N_ANTENAS)
res_eficiente = evaluar_solucion(p_eficiente)
fit_eficiente = fitness(p_eficiente)

@printf("   P = 1.00 W: Fitness = %.4f | Cobertura = %.1f%% | Interf = %.4f\n",
        fit_max, res_max.cobertura_porcentaje, res_max.interferencia_norm)
@printf("   P = 0.35 W: Fitness = %.4f | Cobertura = %.1f%% | Interf = %.4f\n",
        fit_eficiente, res_eficiente.cobertura_porcentaje, res_eficiente.interferencia_norm)
@printf("   Diferencia a favor: +%.4f\n", fit_eficiente - fit_max)

if fit_eficiente > fit_max
    println("   OK: La potencia moderada obtiene mejor fitness que saturar todo a 1.0 W.\n")
else
    error("   Error: lambda no penaliza la interferencia adecuadamente.")
end

# 5. Comparación con el modelo base hay_cobertura
println(">> Prueba 5: Comparación matricial vs hay_cobertura")
puntos_prueba = [poblacion[1], poblacion[500], poblacion[1250], poblacion[2000], poblacion[2500]]
antenas_prueba = [antenas[1], antenas[25], antenas[50], antenas[75], antenas[100]]
potencias_prueba = [0.0, 0.1, 0.3, 0.7, 1.0]

errores = 0
for p in puntos_prueba
    for a in antenas_prueba
        for pot in potencias_prueba
            r_base = hay_cobertura(p, a, pot)
            d2 = (p[1] - a[1])^2 + (p[2] - a[2])^2 + DZ^2
            p_req = d2 * Rural5GModel.K_POTENCIA
            r_mat = (pot > 0.0) && (pot >= p_req)
            if r_base != r_mat
                global errores += 1
            end
        end
    end
end

@printf("   - Comparaciones: %d | Discrepancias: %d\n", length(puntos_prueba)*length(antenas_prueba)*length(potencias_prueba), errores)
@assert errores == 0 "Error: Discrepancia con hay_cobertura"
println("   OK\n")

# 6. Tiempo de ejecución
println(">> Prueba 6: Tiempo de ejecución de fitness()")
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

@printf("   - %d evaluaciones en %.4f s\n", n_evaluaciones, t_total)
@printf("   - Promedio: %.3f ms por evaluación (≈ %.0f eval/s)\n", t_promedio_ms, n_evaluaciones / t_total)
println("   OK\n")

println("Todas las pruebas finalizaron correctamente.")
