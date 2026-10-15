# ==============================================================================
# PROYECTO: Optimización de Cobertura 5G Rural usando Heurísticas (UNMSM)
# SCRIPT: heuristics/run_sa_experiments.jl
# EJECUCIÓN OFICIAL DE EXPERIMENTOS SA (5 SEMILLAS)
# ==============================================================================

using Random
using Statistics
using Printf
using DelimitedFiles

# Cargar módulo oficial de evaluación
include(joinpath(@__DIR__, "..", "core", "fitness.jl"))
using .Rural5GFitness
using .Rural5GFitness.Rural5GModel

const RUTA_SALIDA = normpath(joinpath(@__DIR__, "..", "analytics", "output"))
mkpath(RUTA_SALIDA)

println("=" ^ 80)
println("  EJECUCIÓN DE EXPERIMENTOS DE RECOCIDO SIMULADO (SA) - 5 SEMILLAS")
println("=" ^ 80)
println("Antenas: ", N_ANTENAS, " | Puntos Población: ", N_POBLACION, " | Lambda: ", LAMBDA_DEFAULT)

function vecino_potencias(pot_w::Vector{Float64}, p_max_w::Float64; k_max::Int=5, sigma_pct::Float64=0.1)
    vecino_w = copy(pot_w)
    k = rand(1:k_max)
    indices = randperm(length(pot_w))[1:k]
    ruido_w = sigma_pct * p_max_w

    for i in indices
        vecino_w[i] += randn() * ruido_w
        vecino_w[i] = clamp(vecino_w[i], 0.0, p_max_w)
    end
    return vecino_w
end

function calibrar_t0(fitness_fn, pot_w::Vector{Float64}, p_max_w::Float64; n_muestras::Int=500, target_acc::Float64=0.8)
    fit_inicial = fitness_fn(pot_w)
    deltas_negativos = Float64[]

    for _ in 1:n_muestras
        v_w = vecino_potencias(pot_w, p_max_w)
        fit_vecino = fitness_fn(v_w)
        delta = fit_vecino - fit_inicial
        if delta < 0
            push!(deltas_negativos, abs(delta))
        end
    end

    if isempty(deltas_negativos)
        return 1.0
    end
    delta_promedio = mean(deltas_negativos)
    return -delta_promedio / log(target_acc)
end

struct ResultadoSA
    semilla::Int
    mejor_potencia_w::Vector{Float64}
    mejor_fit::Float64
    hist_mejor_fit::Vector{Float64}
    hist_temp::Vector{Float64}
    tiempo_s::Float64
    evaluaciones::Int
end

function run_sa(fitness_fn, p_max_w::Float64, n_antenas::Int;
                n_iters::Int=50_000,
                alpha_ratio::Float64=1e-4,
                semilla::Int=42)
    Random.seed!(semilla)

    pot_w = rand(n_antenas) .* p_max_w
    fit_actual = fitness_fn(pot_w)

    mejor_pot_w = copy(pot_w)
    mejor_fit = fit_actual

    t0 = calibrar_t0(fitness_fn, pot_w, p_max_w)
    temp = t0
    alpha = alpha_ratio ^ (1.0 / n_iters)

    hist_mejor_fit = zeros(n_iters)
    hist_temp = zeros(n_iters)

    t_inicio = time()

    for i in 1:n_iters
        v_w = vecino_potencias(pot_w, p_max_w)
        fit_v = fitness_fn(v_w)

        delta = fit_v - fit_actual

        if delta >= 0 || rand() < exp(delta / temp)
            pot_w = v_w
            fit_actual = fit_v

            if fit_actual > mejor_fit
                mejor_pot_w = copy(pot_w)
                mejor_fit = fit_actual
            end
        end

        hist_mejor_fit[i] = mejor_fit
        hist_temp[i] = temp
        temp *= alpha
    end

    tiempo_s = time() - t_inicio
    evaluaciones = n_iters + 501 # 500 de calibracion + 1 inicial + 50k iteraciones

    return ResultadoSA(semilla, mejor_pot_w, mejor_fit, hist_mejor_fit, hist_temp, tiempo_s, evaluaciones)
end

eval_fn(p) = Rural5GFitness.fitness(p; lambda=LAMBDA_DEFAULT)

semillas = [42, 123, 256, 789, 1024]
resultados_sa = ResultadoSA[]

for s in semillas
    print("Ejecutando SA con semilla $s (50,000 iteraciones)... ")
    res = run_sa(eval_fn, P_MAX, N_ANTENAS, n_iters=50_000, semilla=s)
    @printf("Completado en %.2fs | Mejor Fitness: %.6f\n", res.tiempo_s, res.mejor_fit)
    push!(resultados_sa, res)
end

println("\n" * "=" ^ 80)
println("  RESUMEN ESTADÍSTICO SA")
println("=" ^ 80)
fits = [r.mejor_fit for r in resultados_sa]
tiempos = [r.tiempo_s for r in resultados_sa]
@printf("Fitness Promedio: %.6f ± %.6f\n", mean(fits), std(fits))
@printf("Tiempo Promedio:  %.2fs ± %.2fs\n", mean(tiempos), std(tiempos))

idx_mejor = argmax(fits)
mejor_global = resultados_sa[idx_mejor]
@printf("Mejor Corrida:    Semilla %d (Fitness: %.6f)\n", mejor_global.semilla, mejor_global.mejor_fit)

det = evaluar_solucion(mejor_global.mejor_potencia_w; lambda=LAMBDA_DEFAULT)
@printf("  - Cobertura:     %d / %d (%.2f%%)\n", det.cobertura_puntos, N_POBLACION, det.cobertura_porcentaje)
@printf("  - Interferencia: %.6f (normalizada)\n", det.interferencia_norm)
@printf("  - Potencia Total: %.2f W\n", det.potencia_total_watts)

# ==============================================================================
# EXPORTACIÓN DE RESULTADOS EN FORMATO ESTÁNDAR
# ==============================================================================
function _guardar_csv(ruta::String, cabecera::Vector{String}, filas::AbstractMatrix)
    open(ruta, "w") do io
        println(io, join(cabecera, ","))
        writedlm(io, filas, ',')
    end
end

tag = "lambda_$(LAMBDA_DEFAULT)"

# 1. Resumen por semilla (mismo esquema exacto que ga_resumen_lambda_0.5.csv)
res_mat = Matrix{Any}(undef, length(resultados_sa), 9)
for (k, r) in enumerate(resultados_sa)
    d = evaluar_solucion(r.mejor_potencia_w; lambda=LAMBDA_DEFAULT)
    res_mat[k, :] = Any[
        "SA",
        LAMBDA_DEFAULT,
        r.semilla,
        r.mejor_fit,
        d.cobertura_porcentaje,
        d.interferencia_norm,
        d.potencia_total_watts,
        r.evaluaciones,
        r.tiempo_s
    ]
end
_guardar_csv(
    joinpath(RUTA_SALIDA, "sa_resumen_$(tag).csv"),
    ["Algoritmo", "Lambda", "Semilla", "Mejor_Fitness", "Cobertura_pct", "Interferencia_norm", "Potencia_total_W", "Evaluaciones", "Tiempo_s"],
    res_mat
)

# 2. Potencias de todas las semillas (mismo esquema exacto que ga_potencias_lambda_0.5.csv)
n_total_pot = length(resultados_sa) * N_ANTENAS
pot_mat = Matrix{Any}(undef, n_total_pot, 7)
fila = 0
for r in resultados_sa, j in 1:N_ANTENAS
    global fila += 1
    pot_mat[fila, :] = Any[
        "SA",
        LAMBDA_DEFAULT,
        r.semilla,
        j,
        antenas[j][1],
        antenas[j][2],
        r.mejor_potencia_w[j]
    ]
end
_guardar_csv(
    joinpath(RUTA_SALIDA, "sa_potencias_$(tag).csv"),
    ["Algoritmo", "Lambda", "Semilla", "Antena_ID", "Pos_X", "Pos_Y", "Potencia_W"],
    pot_mat
)

# 3. Curvas de convergencia individuales
paso_muestreo = 50
n_puntos_conv = div(50_000, paso_muestreo)
for r in resultados_sa
    indices = paso_muestreo:paso_muestreo:50_000
    sub_evals = indices .+ 501
    sub_fits = r.hist_mejor_fit[indices]
    _guardar_csv(
        joinpath(RUTA_SALIDA, "sa_convergencia_semilla_$(r.semilla)_$(tag).csv"),
        ["Paso", "Evaluaciones", "Mejor_Fitness"],
        hcat(1:length(indices), sub_evals, sub_fits)
    )
end

# 4. Curva de convergencia promedio SA
mat_fits = hcat([r.hist_mejor_fit[paso_muestreo:paso_muestreo:50_000] for r in resultados_sa]...)
prom_sa = vec(mean(mat_fits, dims=2))
std_sa = vec(std(mat_fits, dims=2))
evals_sa = (paso_muestreo:paso_muestreo:50_000) .+ 501
_guardar_csv(
    joinpath(RUTA_SALIDA, "sa_convergencia_$(tag).csv"),
    ["Paso", "Evaluaciones", "Fitness_Promedio", "Fitness_Std"],
    hcat(1:n_puntos_conv, evals_sa, prom_sa, std_sa)
)

# 5. Archivos de compatibilidad directa para el notebook de Yosue
# 5.1. potencias_por_lambda.csv (mejor solución del SA con coordenadas)
pot_yosue = Matrix{Any}(undef, N_ANTENAS, 4)
for j in 1:N_ANTENAS
    pot_yosue[j, :] = Any[
        j,
        antenas[j][1],
        antenas[j][2],
        mejor_global.mejor_potencia_w[j]
    ]
end
_guardar_csv(
    joinpath(RUTA_SALIDA, "potencias_por_lambda.csv"),
    ["ID_Antena", "Pos_X", "Pos_Y", "Potencia_W"],
    pot_yosue
)

# 5.2. historial_SA_mejor.csv
open(joinpath(RUTA_SALIDA, "historial_SA_mejor.csv"), "w") do io
    println(io, "Iteracion,Fitness")
    for (i, fit) in enumerate(mejor_global.hist_mejor_fit)
        println(io, "$i,$fit")
    end
end

# 5.3. sa_datos_convergencia.csv
open(joinpath(RUTA_SALIDA, "sa_datos_convergencia.csv"), "w") do io
    println(io, join(["Semilla_$(r.semilla)" for r in resultados_sa], ","))
    mat_full = hcat([r.hist_mejor_fit for r in resultados_sa]...)
    writedlm(io, mat_full, ',')
end

# 5.4. convergencia_comparativa.csv (curva comparativa GA vs SA sincronizada por pasos)
# Leemos ga_convergencia_lambda_0.5.csv si existe
ruta_ga_conv = joinpath(RUTA_SALIDA, "ga_convergencia_$(tag).csv")
if isfile(ruta_ga_conv)
    ga_data, ga_header = readdlm(ruta_ga_conv, ',', Float64; header=true)
    # ga_data tiene columnas: [Generacion, Evaluaciones, Fitness_Promedio, Fitness_Std]
    ga_fits = ga_data[:, 3]
    n_pts = min(length(ga_fits), length(prom_sa))
    
    comp_mat = hcat(1:n_pts, ga_fits[1:n_pts], prom_sa[1:n_pts])
    _guardar_csv(
        joinpath(RUTA_SALIDA, "convergencia_comparativa.csv"),
        ["Paso", "GA_Fitness", "SA_Fitness"],
        comp_mat
    )
    println("✅ Archivo convergencia_comparativa.csv generado con éxito.")
end

# 6. Tabla comparativa consolidada GA vs SA (Task 3.1)
ruta_ga_resumen = joinpath(RUTA_SALIDA, "ga_resumen_$(tag).csv")
if isfile(ruta_ga_resumen)
    ga_res, _ = readdlm(ruta_ga_resumen, ',', Any; header=true)
    ga_fits_arr = Float64.(ga_res[:, 4])
    ga_tiempos_arr = Float64.(ga_res[:, 9])
    ga_cob_arr = Float64.(ga_res[:, 5])
    ga_interf_arr = Float64.(ga_res[:, 6])
    ga_pot_arr = Float64.(ga_res[:, 7])
    ga_evals_arr = Int.(ga_res[:, 8])
    
    sa_fits_arr = fits
    sa_tiempos_arr = tiempos
    sa_cob_arr = [evaluar_solucion(r.mejor_potencia_w; lambda=LAMBDA_DEFAULT).cobertura_porcentaje for r in resultados_sa]
    sa_interf_arr = [evaluar_solucion(r.mejor_potencia_w; lambda=LAMBDA_DEFAULT).interferencia_norm for r in resultados_sa]
    sa_pot_arr = [evaluar_solucion(r.mejor_potencia_w; lambda=LAMBDA_DEFAULT).potencia_total_watts for r in resultados_sa]
    sa_evals_arr = [r.evaluaciones for r in resultados_sa]
    
    tabla_comp = [
        "Metrica" "Algoritmo_Genetico_GA" "Recocido_Simulado_SA";
        "Mejor Fitness" @sprintf("%.6f", maximum(ga_fits_arr)) @sprintf("%.6f", maximum(sa_fits_arr));
        "Fitness Promedio" @sprintf("%.6f ± %.6f", mean(ga_fits_arr), std(ga_fits_arr)) @sprintf("%.6f ± %.6f", mean(sa_fits_arr), std(sa_fits_arr));
        "Cobertura Promedio (%%)" @sprintf("%.2f%% ± %.2f%%", mean(ga_cob_arr), std(ga_cob_arr)) @sprintf("%.2f%% ± %.2f%%", mean(sa_cob_arr), std(sa_cob_arr));
        "Interferencia Promedio" @sprintf("%.6f ± %.6f", mean(ga_interf_arr), std(ga_interf_arr)) @sprintf("%.6f ± %.6f", mean(sa_interf_arr), std(sa_interf_arr));
        "Potencia Total Promedio (W)" @sprintf("%.2f W ± %.2f W", mean(ga_pot_arr), std(ga_pot_arr)) @sprintf("%.2f W ± %.2f W", mean(sa_pot_arr), std(sa_pot_arr));
        "Evaluaciones por Corrida" @sprintf("%d", Int(round(mean(ga_evals_arr)))) @sprintf("%d", Int(round(mean(sa_evals_arr))));
        "Tiempo de Computo Promedio (s)" @sprintf("%.2fs ± %.2fs", mean(ga_tiempos_arr), std(ga_tiempos_arr)) @sprintf("%.2fs ± %.2fs", mean(sa_tiempos_arr), std(sa_tiempos_arr));
    ]
    
    open(joinpath(RUTA_SALIDA, "tabla_comparativa_ga_vs_sa.csv"), "w") do io
        for i in 1:size(tabla_comp, 1)
            println(io, join(tabla_comp[i, :], ","))
        end
    end
    println("✅ Archivo tabla_comparativa_ga_vs_sa.csv generado con éxito.")
end

println("\n" * "=" ^ 80)
println("  TODOS LOS CSVs DE SA HAN SIDO GENERADOS EN analytics/output/")
println("=" ^ 80)
