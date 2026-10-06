# ==============================================================================
# PROYECTO: Optimización de Cobertura 5G Rural usando Heurísticas (UNMSM)
# SCRIPT: heuristics/run_pipeline.jl
# RESPONSABLE: Jack (Task 1.3: Pipeline de Verificación de Punta a Punta)
# ==============================================================================

using Random
using Printf

include("../core/fitness.jl")
using .Rural5GFitness
using .Rural5GFitness.Rural5GModel

println("================================================================================")
println("  TASK 1.3: RUNNER DE VERIFICACIÓN DE PUNTA A PUNTA (PIPELINE E2E)")
println("================================================================================")
println("Módulo listo para orquestar las heurísticas del Frente 2:")
println("  - Algoritmo Genético (GA) -> Task 2.1 (Gael)")
println("  - Recocido Simulado (SA)  -> Task 2.2 (Manuel)")
println("--------------------------------------------------------------------------------\n")

# Estructura unificada para recolectar resultados de cada semilla
struct CorridaHeuristica
    algoritmo::String
    semilla::Int
    mejor_fitness::Float64
    cobertura_pct::Float64
    interferencia_norm::Float64
    potencia_total_watts::Float64
    evaluaciones::Int
    tiempo_segundos::Float64
    mejor_vector::Vector{Float64}
end

"""
    verificar_consistencia_resultado(res::CorridaHeuristica)

Verifica que el fitness reportado por la heurística coincida de forma exacta
e independiente al re-evaluar el vector solución con la función fitness() del Task 1.2.
"""
function verificar_consistencia_resultado(res::CorridaHeuristica)
    eval_independiente = evaluar_solucion(res.mejor_vector; lambda = LAMBDA_DEFAULT)
    discrepancia = abs(eval_independiente.fitness - res.mejor_fitness)
    
    @printf("Verificación independiente para [%s - Semilla %d]:\n", res.algoritmo, res.semilla)
    @printf("  - Fitness reportado: %.6f\n", res.mejor_fitness)
    @printf("  - Fitness verificado: %.6f (Error: %.2e)\n", eval_independiente.fitness, discrepancia)
    @printf("  - Cobertura: %.2f%% | Interferencia: %.4f | Potencia: %.2f W\n",
            eval_independiente.cobertura_porcentaje, eval_independiente.interferencia_norm, eval_independiente.potencia_total_watts)
    
    if discrepancia < 1e-6
        println("  -> [OK] Consistencia matemática confirmada (Sin desincronización).\n")
        return true
    else
        @warn "  -> [ERROR] Discrepancia detectada entre heurística y fitness() oficial!"
        return false
    end
end

# Ejemplo de prueba de integración de interfaz
println("Verificando protocolo de interfaz con vector de prueba...")
semilla_test = 101
Random.seed!(semilla_test)
vector_test = clamp.(rand(N_ANTENAS) .* 0.5 .+ 0.2, 0.0, 1.0)
eval_test = evaluar_solucion(vector_test)

resultado_demo = CorridaHeuristica(
    "TestHarness",
    semilla_test,
    eval_test.fitness,
    eval_test.cobertura_porcentaje,
    eval_test.interferencia_norm,
    eval_test.potencia_total_watts,
    1,
    0.001,
    vector_test
)

verificar_consistencia_resultado(resultado_demo)

println("Pipeline E2E preparado para recibir GA y SA cuando completen Frente 2.")
println("================================================================================")
