# ==============================================================================
# PROYECTO: Optimización de Cobertura 5G Rural usando Heurísticas (UNMSM)
# SCRIPT: heuristics/run_pipeline.jl
# RESPONSABLE: Jack (Task 1.3: Pipeline de Verificación de Punta a Punta)
# ==============================================================================

using Random
using Statistics
using Printf
using DelimitedFiles

include(joinpath(@__DIR__, "..", "core", "fitness.jl"))
using .Rural5GFitness
using .Rural5GFitness.Rural5GModel

const RUTA_ANALYTICS = normpath(joinpath(@__DIR__, "..", "analytics", "output"))

println("=" ^ 80)
println("  TASK 1.3: PIPELINE DE VERIFICACIÓN DE PUNTA A PUNTA (E2E)")
println("=" ^ 80)
println("Verificando consistencia e interoperabilidad de heurísticas:")
println("  - Frente 1: Función objetivo calibrada (λ = $LAMBDA_DEFAULT)")
println("  - Task 2.1: Algoritmo Genético (GA - Gael)")
println("  - Task 2.2: Recocido Simulado (SA - Manuel)")
println("-" ^ 80 * "\n")

struct VerificacionResultado
    algoritmo::String
    semilla::Int
    fitness_reportado::Float64
    fitness_verificado::Float64
    error_absoluto::Float64
    cobertura_pct::Float64
    interferencia_norm::Float64
    potencia_total_w::Float64
    consistente::Bool
end

function verificar_archivo_potencias(ruta_resumen::String, ruta_potencias::String, algoritmo_nombre::String)
    if !isfile(ruta_resumen) || !isfile(ruta_potencias)
        @warn "No se encontraron los archivos para $algoritmo_nombre en $RUTA_ANALYTICS"
        return VerificacionResultado[]
    end

    res_data, _ = readdlm(ruta_resumen, ',', Any; header=true)
    pot_data, _ = readdlm(ruta_potencias, ',', Any; header=true)

    # pot_data tiene: [Algoritmo, Lambda, Semilla, Antena_ID, Pos_X, Pos_Y, Potencia_W]
    semillas_unicas = unique(res_data[:, 3])
    verificaciones = VerificacionResultado[]

    for s in semillas_unicas
        fila_res = findfirst(r -> r == s, res_data[:, 3])
        fit_rep = Float64(res_data[fila_res, 4])

        # Extraer las 100 potencias para esta semilla
        filas_pot = findall(r -> r == s, pot_data[:, 3])
        potencias = Float64.(pot_data[filas_pot, 7])

        # Verificación matemática independiente con core/fitness.jl
        eval_ind = Rural5GFitness.evaluar_solucion(potencias; lambda = LAMBDA_DEFAULT)
        err = abs(eval_ind.fitness - fit_rep)
        ok = err < 1e-6

        push!(verificaciones, VerificacionResultado(
            algoritmo_nombre,
            s,
            fit_rep,
            eval_ind.fitness,
            err,
            eval_ind.cobertura_porcentaje,
            eval_ind.interferencia_norm,
            eval_ind.potencia_total_watts,
            ok
        ))

        status_tag = ok ? "✅ OK" : "❌ ERROR"
        @printf("[%s] %-4s | Semilla %4d | Fit Rep: %.6f | Fit Indep: %.6f | Error: %.2e | Cob: %.2f%% | Pot: %.2f W\n",
                status_tag, algoritmo_nombre, s, fit_rep, eval_ind.fitness, err,
                eval_ind.cobertura_porcentaje, eval_ind.potencia_total_watts)
    end

    return verificaciones
end

tag = "lambda_$(LAMBDA_DEFAULT)"
ruta_ga_res = joinpath(RUTA_ANALYTICS, "ga_resumen_$(tag).csv")
ruta_ga_pot = joinpath(RUTA_ANALYTICS, "ga_potencias_$(tag).csv")

ruta_sa_res = joinpath(RUTA_ANALYTICS, "sa_resumen_$(tag).csv")
ruta_sa_pot = joinpath(RUTA_ANALYTICS, "sa_potencias_$(tag).csv")

println("--- 1. VERIFICACIÓN INDEPENDIENTE DEL ALGORITMO GENÉTICO (GA) ---")
v_ga = verificar_archivo_potencias(ruta_ga_res, ruta_ga_pot, "GA")

println("\n--- 2. VERIFICACIÓN INDEPENDIENTE DEL RECOCIDO SIMULADO (SA) ---")
v_sa = verificar_archivo_potencias(ruta_sa_res, ruta_sa_pot, "SA")

todas_v = vcat(v_ga, v_sa)
n_total = length(todas_v)
n_ok = count(v -> v.consistente, todas_v)

println("\n" * "=" ^ 80)
println("  RESULTADO FINAL DEL PIPELINE E2E")
println("=" ^ 80)
@printf("Corridas verificadas: %d / %d (%.1f%% consistentes)\n", n_ok, n_total, (n_ok / max(1, n_total)) * 100.0)

if n_ok == n_total && n_total > 0
    println("🎉 ÉXITO TOTAL: Todas las soluciones de GA y SA son 100% consistentes con core/fitness.jl")
    println("   No hay discrepancias numéricas ni desincronización en el equipo.")
else
    @warn "Se detectaron inconsistencias en algunas corridas. Revisar logs anteriores."
end
println("=" ^ 80)
