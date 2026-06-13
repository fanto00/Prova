% Database_2_FINAL_With_5g_Limit_and_Geometric_Alignment_AND_CROP
% --- AGGIORNAMENTO: Micro-allineamento sub-campione via zero-padding
%     in frequenza (interpft) e shift frazionario via fase FFT.
% --- AGGIORNAMENTO 2: Secondo passaggio per completare la storia dei
%     difetti confermati (>=80 run) con la risposta anche senza trigger.
clear; clc; close all;
tic;
% =========================================================================
% 1. CONFIGURAZIONE GENERALE
% =========================================================================
CFG.root_folder = 'C:\Users\Nicco\MATLAB Drive\TESI\M2_pari';
CFG.excel_path  = 'C:\Users\Nicco\MATLAB Drive\TESI\M2-PEDRO.xlsx'; 
CFG.save_folder = 'C:\Users\Nicco\MATLAB Drive\TESI\Defect_Database_pari';
CFG.TRACK_TYPE = 'pari'; 

% --- SELEZIONE TRATTA (opzionale) ---
% Lascia vuoto '' per processare TUTTE le tratte.
% Altrimenti specifica un pattern: numero ('42'), nome parziale ('Piola'),
% o nome completo ('42-Piola to Loreto'). Match case-insensitive.
CFG.ROUTE_FILTER = '37';
% --- SELEZIONE DIREZIONE DI MARCIA ---
% true  -> salva SOLO le run "moving forward"
% false -> salva tutte le run
CFG.ONLY_FORWARD = true;
 
% --- MODALITÀ SOLO GIUNTI ---
% true  -> niente detection a trigger: estrae SOLO le posizioni dei giunti
%          (estrazione forzata anche senza picco, per l'andamento al giunto).
% false -> comportamento normale.
CFG.ONLY_JOINTS    = true;
CFG.JOINTS_EXCEL   = 'C:\Users\Nicco\MATLAB Drive\TESI\Position-Giunti.xlsx';
CFG.JOINT_WINDOW   = 7.0;   % Semi-finestra dedicata (+/- m). Dato lo scostamento
                            % PK max ~5 m, valuta 7-8 per avere margine attorno.
CFG.JOINT_MAX_RUNS = 300;   % Tetto massimo run salvate per ogni giunto.


fmin = 2;
fmax = 350;
% --- PARAMETRI SPAZIALI ---
CFG.SPATIAL_RES = 0.004; %m 
CFG.WINDOW_FINAL   = 5.0;  % Finestra finale desiderata (+/- 5m = 10m totali)
CFG.WINDOW_EXTRACT = 7.0;  % Finestra di estrazione con margine (+/- 7m = 14m totali)
CFG.ALIGN_FOCUS    = 2;    % Raggio in metri (+/- 1m) per "isolare" il picco da allineare
CFG.FILTER_MARGIN  = 50.0; % Margine di sicurezza per i transienti del filtro prima del crop secondo pass
CFG.ALIGN_MAX_LAG  = 4;  % Massimo shift in metri consentito per l'allineamento micro
CFG.UPSAMPLE_FACTOR = 4;   % Fattore di upsampling per allineamento sub-campione
CFG.ALIGN_TEMPLATE_ITERS = 3;   % passate di raffinamento del template medio (3 = converge)
CFG.ALIGN_TEMPLATE_NRUNS = 5;   % run per costruire il template (0 = tutte; N = le N piu' rappresentative)
CFG.INFRA_TOL   = 2.5; %distanza tra infrastrutture tipo deviatoi o giunti
CFG.CROSS_TOL   = 1.5; %distanza tra i picchi
% --- FILTRO SWITCH ---
% true  -> scarta gli eventi che cadono nei range degli scambi (section_extracted.switch)
% false -> non filtra
CFG.FILTER_SWITCHES = true;
% --- PARAMETRI FILTRAGGIO ADATTIVO ---
CFG.L_MAX = 15;           
CFG.L_MIN_QUIET = 0.01;    
% --- SOGLIE E SHOCK ---
CFG.RMS_WIN_FAST = 1;  
CFG.RMS_WIN_SLOW = 20.0; 
CFG.RMS_MUL      = 3;    
CFG.MIN_DIST     = 1.5;  
CFG.ABS_RMS_THRESH = 5.0; %in m/s^2
CFG.SAVE_RAW = false;  
CFG.SPEED_TOL   = 10;
% --- COMPLETAMENTO DATABASE ---
CFG.MIN_RUNS_COMPLETE = 10; % Minimo run con trigger per attivare il completamento
CFG.MAX_TOTAL_RUNS = 150;   % Limite massimo assoluto di run da salvare per un singolo difetto
% =========================================================================
% 2. CARICAMENTO MAPPA INFRASTRUTTURA
% =========================================================================
fprintf('Caricamento mappa deviatoi e raccordi...\n');
try
    TrackMap = load_infrastructure_map(CFG.excel_path, CFG.TRACK_TYPE);
    fprintf('Mappa caricata: %d elementi trovati.\n', height(TrackMap));
catch ME
    warning('Procedo senza matching infrastruttura: %s', ME.message);
    TrackMap = table();
end

% --- CARICAMENTO MAPPA GIUNTI (solo se modalità giunti) ---
JointsMap = table();
if CFG.ONLY_JOINTS
    JointsMap = load_joints_map(CFG.JOINTS_EXCEL, CFG.TRACK_TYPE);
    fprintf('Mappa giunti caricata: %d giunti totali.\n', height(JointsMap));
end

% =========================================================================
% 3. LOOP PRINCIPALE
% =========================================================================
subDirs = dir(CFG.root_folder);
subDirs = subDirs([subDirs.isdir] & ~ismember({subDirs.name}, {'.', '..'}));

% --- APPLICA FILTRO TRATTA ---
if isfield(CFG, 'ROUTE_FILTER') && ~isempty(CFG.ROUTE_FILTER)
    keep = contains({subDirs.name}, CFG.ROUTE_FILTER, 'IgnoreCase', true);
    subDirs = subDirs(keep);
    if isempty(subDirs)
        error('Nessuna tratta corrisponde al filtro "%s".', CFG.ROUTE_FILTER);
    end
    fprintf('Filtro tratta attivo "%s": %d tratte selezionate.\n', ...
        CFG.ROUTE_FILTER, length(subDirs));
end

for r = 1:length(subDirs)
    curr_route_name = subDirs(r).name;
    curr_route_path = fullfile(CFG.root_folder, curr_route_name);

    fprintf('\nSTART TRATTA: %s\n', curr_route_name);


    % --- GIUNTI DI QUESTA TRATTA ---
RouteJoints = []; RouteJointLabels = strings(0,1);
if CFG.ONLY_JOINTS
    mask_tr = strcmpi(strtrim(string(JointsMap.Stations)), strtrim(string(curr_route_name)));
    Jt = JointsMap(mask_tr, :);
    if height(Jt) > 0
        [~, ord] = sort(Jt.Position);
        Jt = Jt(ord, :);
        RouteJoints      = Jt.Position;
        RouteJointLabels = string(Jt.Joint);
        fprintf('   Giunti in tratta: %d\n', numel(RouteJoints));
    else
        fprintf('   Nessun giunto per "%s": skip tratta.\n', curr_route_name);
        continue;
    end
end

    file_list = dir(fullfile(curr_route_path, '**', '*.mat'));
    valid_files = file_list(~startsWith({file_list.name}, '.') & ~contains({file_list.name}, 'Database_damage'));

    if isempty(valid_files), continue; end

    Global_Event_List = struct('Pos', {}, 'Amp', {}, 'Date', {}, 'RunName', {}, 'Signals', {}, 'Infra_Match', {});
    ev_count = 0;

    % --- VARIABILI PER ALLINEAMENTO E TAGLIO ---
    ReferenceSignal = [];
    CROP_START = [];
    CROP_END   = [];

    % --- SALVATAGGIO INFO PER SECONDO PASSAGGIO ---
    % Memorizziamo lo shift geometrico di ogni file per poterlo ri-applicare
    RunInfo = struct('FilePath', {}, 'RunName', {}, 'Date', {}, 'GeoShift', {}, 'Valid', {});


    CachedData = cell(length(valid_files), 1);

    for i = 1:length(valid_files)
        f_path = fullfile(valid_files(i).folder, valid_files(i).name);
        [~, f_name, ~] = fileparts(valid_files(i).name);

        % Parsing Data & Base Date
        try
            % Carica SOLO la variabile che ti serve, ignorando il resto
            d = load(f_path, 'section_extracted');
            data_struct = d.section_extracted;
            if isfield(data_struct, 'time_start')
                run_date = datetime(data_struct.time_start);
            else
                parts = split(f_name, '_');
                run_date = datetime([parts{2} ' ' parts{3}], 'InputFormat', 'yyyyMMdd HHmmss');
            end
        catch
            run_date = datetime('now');
            data_struct = struct();
        end

        fprintf('   -> File [%d/%d]: %s ', i, length(valid_files), f_name);

        % Salviamo info base (anche se poi fallisce)
        RunInfo(i).FilePath = f_path;
        RunInfo(i).RunName  = string(f_name);
        RunInfo(i).Date     = run_date;
        RunInfo(i).GeoShift = 0;
        RunInfo(i).Valid    = false;

        try
            if isempty(fieldnames(data_struct)), continue; end

           % =============================================================
            % 1. BLOCCO ALLINEAMENTO GEOMETRICO (MACRO)
            % =============================================================
            space_raw = double(data_struct.space_neutral);

            % --- Determinazione orientation (con fallback su space_parameters) ---
            curr_orientation = "";
            if isfield(data_struct, 'orientation')
                curr_orientation = strtrim(string(data_struct.orientation));
            elseif isfield(data_struct, 'space_parameters') && isfield(data_struct.space_parameters, 'front')
                if data_struct.space_parameters.front < 0
                    curr_orientation = "moving backward";
                else
                    curr_orientation = "moving forward";
                end
            end

                        % --- FILTRO DIREZIONE ---
            if CFG.ONLY_FORWARD && curr_orientation == "moving backward"
                fprintf(' -> SKIP (backward, ONLY_FORWARD attivo)\n');
                RunInfo(i).Valid = false;
                continue;
            end

            if isfield(data_struct, 'curve')
                sig_geo = abs(double(data_struct.curve));
            else
                sig_geo = abs(double(data_struct.left_sensor_front));
            end
            sig_geo(isnan(sig_geo)) = 0;

            common_axis_ext = (min(space_raw)-150) : CFG.SPATIAL_RES : (max(space_raw)+150);
            [ax_u, idx_u] = unique(space_raw, 'stable');
            sig_geo_res = interp1(ax_u, sig_geo(idx_u), common_axis_ext, 'linear', 0);
            sig_geo_res = (sig_geo_res - mean(sig_geo_res)) / (std(sig_geo_res) + 1e-6);

            current_shift = 0;

            if isempty(ReferenceSignal)
                ReferenceSignal   = sig_geo_res;
                MasterOrientation = curr_orientation;
                CROP_START        = min(space_raw);
                CROP_END          = max(space_raw);
                fprintf('(MASTER [%s, Start: %.1f, End: %.1f]) ', MasterOrientation, CROP_START, CROP_END);
            else
                max_lag = round(150 / CFG.SPATIAL_RES);
                L_min = min(length(ReferenceSignal), length(sig_geo_res));
                [corr_vals, lags] = xcorr(ReferenceSignal(1:L_min), sig_geo_res(1:L_min), max_lag);
                [~, max_idx] = max(corr_vals);
                current_shift = lags(max_idx) * CFG.SPATIAL_RES;
                
                % --- SANITY CHECK: shift coerente con la direzione di marcia? ---
                same_dir = (curr_orientation == MasterOrientation);
                if same_dir && abs(current_shift) > 50
                    fprintf(' -> SKIP (%s ma shift=%+.1fm, sospetto)\n', curr_orientation, current_shift);
                    RunInfo(i).Valid = false;
                    continue;
                elseif ~same_dir && abs(current_shift) < 50
                    fprintf(' -> SKIP (%s vs MASTER %s ma shift=%+.1fm, sospetto)\n', ...
                        curr_orientation, MasterOrientation, current_shift);
                    RunInfo(i).Valid = false;
                    continue;
                end
                
                fprintf('(%s, Shift: %+.2fm) ', curr_orientation, current_shift);
            end
            % Salviamo lo shift per il secondo passaggio
            RunInfo(i).GeoShift = current_shift;
            RunInfo(i).Valid    = true;

            data_struct.space_neutral = data_struct.space_neutral + current_shift;
            if isfield(data_struct, 'space_front'), data_struct.space_front = data_struct.space_front + current_shift; end
            if isfield(data_struct, 'space_back'), data_struct.space_back = data_struct.space_back + current_shift; end
            % Porto i range degli switch nello stesso frame shiftato della detection
            if CFG.FILTER_SWITCHES && isfield(data_struct, 'switch') && isfield(data_struct.switch, 'location')
                data_struct.switch.location = double(data_struct.switch.location) + current_shift;
            end
            % =============================================================
            % 2. BLOCCO TAGLIO (CROP)
            % =============================================================
            mask_keep = (data_struct.space_neutral >= CROP_START) & ...
                (data_struct.space_neutral <= CROP_END);

            if sum(mask_keep) < 100
                fprintf(' -> SKIP (Fuori range dopo il taglio).\n');
                RunInfo(i).Valid = false;
                continue;
            end

            fields = fieldnames(data_struct);
            len_mask = length(mask_keep);
            for fn = 1:length(fields)
                fname = fields{fn};
                val = data_struct.(fname);
                if isnumeric(val) && (length(val) == len_mask)
                    data_struct.(fname) = val(mask_keep);
                end
            end

            CachedData{i} = data_struct;
            % =============================================================
            % Analisi difetti (Sui dati tagliati e allineati)
           if CFG.ONLY_JOINTS
               [File_Events] = extract_at_joints(data_struct, RouteJoints, RouteJointLabels, CFG, fmin, fmax);
           else
               [File_Events] = analyze_and_extract(data_struct, CFG, fmin, fmax);
           end
           

            if ~isempty(File_Events)

                time_array = [];
                if isfield(data_struct, 'time') && ~isempty(data_struct.time)
                    time_array = run_date + seconds(double(data_struct.time));
                end

                for k = 1:length(File_Events)
                    ev_count = ev_count + 1;
                    curr_pos = File_Events(k).Pos;

                    exact_date = run_date;
                    if ~isempty(time_array)
                        [~, idx_closest] = min(abs(double(data_struct.space_neutral) - curr_pos));
                        exact_date = time_array(idx_closest);
                    end

                    infra_note = "Linea";
                    if CFG.ONLY_JOINTS
                        infra_note = "Giunto " + File_Events(k).Label;
                    elseif ~isempty(TrackMap)
                        idx_m = find((TrackMap.Pk_Inizio - CFG.INFRA_TOL) <= curr_pos & ...
                            (TrackMap.Pk_Fine + CFG.INFRA_TOL) >= curr_pos);
                        if ~isempty(idx_m)
                            infra_note = strjoin(strcat(TrackMap.Tipo(idx_m), ": ", TrackMap.Descrizione(idx_m)), ' | ');
                        end
                    end

                    Global_Event_List(ev_count).Pos         = curr_pos;
                    Global_Event_List(ev_count).Amp         = File_Events(k).Amp;
                    Global_Event_List(ev_count).Date        = exact_date;
                    Global_Event_List(ev_count).RunName     = string(f_name);
                    Global_Event_List(ev_count).Signals     = File_Events(k).Signals;
                    Global_Event_List(ev_count).Infra_Match = infra_note;
                    Global_Event_List(ev_count).MacroShift  = current_shift;
                end
                fprintf('OK (%d difetti)\n', length(File_Events));
            else
                fprintf('Nessun difetto rilevato.\n');
            end
        catch ME
            fprintf('ERRORE: %s\n', ME.message);
        end
    end

    if ev_count > 0
        % =================================================================
        % CLUSTERING
        % =================================================================
        T = struct2table(Global_Event_List);
        T = sortrows(T, 'Pos');
        ClusterID = zeros(height(T), 1);
        curr_id = 1; ClusterID(1) = 1;
        for j = 2:height(T)
            if (T.Pos(j) - T.Pos(j-1)) > CFG.CROSS_TOL, curr_id = curr_id + 1; end
            ClusterID(j) = curr_id;
        end
        T.ClusterID = ClusterID;

        UniqueClusters = unique(ClusterID);
        MASTER_DB = struct();

        db_idx = 1;

        for k = 1:length(UniqueClusters)
            subset = T(T.ClusterID == UniqueClusters(k), :);

            % =========================================================
            % FILTRO VELOCITÀ MODA (+/- 2.5 km/h)
            % =========================================================
            speeds = zeros(height(subset), 1);
            for h = 1:height(subset)
                speeds(h) = subset.Signals(h).Speed;
            end

            valid_speeds = speeds(~isnan(speeds) & speeds > 0);
            mode_speed = NaN;
            if ~isempty(valid_speeds)
                mode_speed = mode(round(valid_speeds));
                if ~CFG.ONLY_JOINTS
                    keep_mask = ~isnan(speeds) & (abs(speeds - mode_speed) <= CFG.SPEED_TOL);
                    subset = subset(keep_mask, :);
                end
            end

            if height(subset) == 0
                continue;
            end

            avg_p = mean(subset.Pos);

            MASTER_DB(db_idx).ID_PK = sprintf('%.3f', avg_p/1000);
            MASTER_DB(db_idx).Avg_Pos = avg_p;
            MASTER_DB(db_idx).Max_Severity = max(subset.Amp);
            MASTER_DB(db_idx).Num_Occurrences = height(subset);
            MASTER_DB(db_idx).Infrastructure = subset.Infra_Match(1);
            MASTER_DB(db_idx).Mode_Speed = mode_speed; %salvataggio della moda della velocità del difetto
            % Ordiniamo le run per data cronologica
            [~, s_idx] = sort(subset.Date);
            sorted_s = subset(s_idx, :);

            % =========================================================
            % INIZIO BLOCCO MICRO-ALLINEAMENTO SUB-CAMPIONE
            % =========================================================
            [~, master_idx] = max(sorted_s.Amp);
            MasterSignals = sorted_s.Signals(master_idx);

            avail_sensors = fieldnames(MasterSignals.Filt);
            ref_sensor = '';
            max_energy = -1;
            for s_idx2 = 1:length(avail_sensors)
                energy = sum(double(MasterSignals.Filt.(avail_sensors{s_idx2})).^2);
                if energy > max_energy
                    max_energy = energy;
                    ref_sensor = avail_sensors{s_idx2};
                end
            end

            if ~isempty(ref_sensor)
                MasterFilt = double(MasterSignals.Filt.(ref_sensor));
            else
                MasterFilt = [];
            end

            % --- Calcolo offset per centrare il Master (in METRI) ---
            master_shift_m = 0;
            true_avg_pos = mean(subset.Pos);

            if ~isempty(MasterFilt)
                [~, true_zero_idx] = min(abs(MasterSignals.RelativeAxis));
                
                search_radius_samp = round(CFG.ALIGN_FOCUS / CFG.SPATIAL_RES);
                idx_start_search = max(1, true_zero_idx - search_radius_samp);
                idx_end_search   = min(length(MasterFilt), true_zero_idx + search_radius_samp);
                
                [~, local_peak_idx] = max(abs(MasterFilt(idx_start_search:idx_end_search)));
                master_peak_idx = local_peak_idx + idx_start_search - 1;

                master_shift_m = (true_zero_idx - master_peak_idx) * CFG.SPATIAL_RES;

                % --- DIAG TEMP: il MASTER si e' centrato bene o ha railato la ricerca picco? ---
                win_len = idx_end_search - idx_start_search + 1;
                master_peak_rail = (local_peak_idx <= 1) || (local_peak_idx >= win_len);
                fprintf('   [MASTER] cl %d  giunto=%s  master_shift=%+.2fm  peak_rail=%d\n', ...
                    db_idx, char(MASTER_DB(db_idx).Infrastructure), master_shift_m, master_peak_rail);
                offset_m = (master_peak_idx - true_zero_idx) * CFG.SPATIAL_RES;
                true_avg_pos = sorted_s.Pos(master_idx) + offset_m;
            end

            MASTER_DB(db_idx).ID_PK = sprintf('%.3f', true_avg_pos/1000);
            MASTER_DB(db_idx).Avg_Pos = true_avg_pos;
            MASTER_DB(db_idx).Max_Severity = max(subset.Amp);
            MASTER_DB(db_idx).Num_Occurrences = height(subset);
            MASTER_DB(db_idx).Infrastructure = subset.Infra_Match(1);

            % --- GEOMETRIA + TEMPLATE DI ALLINEAMENTO ROBUSTO ---
            corr_radius_samp = round(CFG.ALIGN_FOCUS / CFG.SPATIAL_RES);
            focus_len        = 2*corr_radius_samp + 1;
            N_up             = focus_len * CFG.UPSAMPLE_FACTOR;
            max_lag_samples  = round(CFG.ALIGN_MAX_LAG / CFG.SPATIAL_RES);
            max_lag_up       = max_lag_samples * CFG.UPSAMPLE_FACTOR;
            Env_Template     = build_align_template(sorted_s, ref_sensor, ...
                                   focus_len, max_lag_samples, N_up, CFG);

            Hist = struct();

            for h = 1:height(sorted_s)
                Hist(h).Date = sorted_s.Date(h);
                
                Hist(h).RunName = string(sorted_s.RunName(h)); % FIX #1: forza string per evitare cell nel confronto del 2° passaggio
                Hist(h).Detected = true; % <--- FLAG: difetto rilevato

                Hist(h).MacroShift = sorted_s.MacroShift(h);

               curr_signals = sorted_s.Signals(h);
                shift_m = 0;

                % --- ALLINEAMENTO AL TEMPLATE (envelope di Hilbert, sub-campione via FFT) ---
                % Ogni run (master incluso) si allinea al template, non piu' alla run piu' forte.
                % Il template e' gia' centrato sul proprio picco: il lag xcorr centra il
                % burst sul nominale, quindi non serve piu' il termine master_shift_m.
                if ~isempty(Env_Template) && ~isempty(ref_sensor) && isfield(curr_signals.Filt, ref_sensor)
                    CurrFilt = double(curr_signals.Filt.(ref_sensor));
                    [~, curr_zero_idx] = min(abs(curr_signals.RelativeAxis));

                    c_start = curr_zero_idx - corr_radius_samp;
                    c_end   = curr_zero_idx + corr_radius_samp;
                    if c_start >= 1 && c_end <= length(CurrFilt)
                        Curr_Focus = CurrFilt(c_start:c_end);     % lunghezza == focus_len
                        Curr_Up    = interpft(Curr_Focus, N_up);
                        Env_Curr   = abs(hilbert(Curr_Up));

                        [corr_vals, lags] = xcorr(Env_Template, Env_Curr, max_lag_up);
                        [~, max_c_idx] = max(corr_vals);
                        shift_m = (lags(max_c_idx) / CFG.UPSAMPLE_FACTOR) * CFG.SPATIAL_RES;
                    end
                end

                %
                % SHIFT FRAZIONARIO
                if shift_m ~= 0
                    for s_idx2 = 1:length(avail_sensors)
                        sn = avail_sensors{s_idx2};
                        if isfield(curr_signals.Filt, sn)
                            curr_signals.Filt.(sn) = shift_signal_frac( ...
                                curr_signals.Filt.(sn), shift_m, CFG.SPATIAL_RES);
                        end
                    end

                    if isfield(curr_signals, 'Raw')
                        raw_sens = fieldnames(curr_signals.Raw);
                        for r_idx = 1:length(raw_sens)
                            rsn = raw_sens{r_idx};
                            if isfield(curr_signals.Raw, rsn)
                                curr_signals.Raw.(rsn) = shift_signal_frac( ...
                                    curr_signals.Raw.(rsn), shift_m, CFG.SPATIAL_RES);
                            end
                        end
                    end
                end

                % CROP FINALE
                if CFG.ONLY_JOINTS, win_final = CFG.JOINT_WINDOW; else, win_final = CFG.WINDOW_FINAL; end
                N_half = round(win_final / CFG.SPATIAL_RES);
                center_crop_idx = round(length(curr_signals.RelativeAxis) / 2);
                crop_start_ideal = center_crop_idx - N_half;
                crop_end_ideal   = center_crop_idx + N_half;
                safe_start = max(1, crop_start_ideal);
                safe_end   = min(length(curr_signals.RelativeAxis), crop_end_ideal);
                
                for s_idx2 = 1:length(avail_sensors)
                    sn = avail_sensors{s_idx2};
                    if isfield(curr_signals.Filt, sn) && length(curr_signals.Filt.(sn)) > 1
                        curr_signals.Filt.(sn) = curr_signals.Filt.(sn)(safe_start:safe_end);
                    end
                end
                
                if isfield(curr_signals, 'Raw')
                    raw_sens = fieldnames(curr_signals.Raw);
                    for r_idx = 1:length(raw_sens)
                        rsn = raw_sens{r_idx};
                        if isfield(curr_signals.Raw, rsn) && length(curr_signals.Raw.(rsn)) > 1
                            curr_signals.Raw.(rsn) = curr_signals.Raw.(rsn)(safe_start:safe_end);
                        end
                    end
                end
                
                idx_vector = (safe_start:safe_end)' - center_crop_idx;
                curr_signals.RelativeAxis = idx_vector * CFG.SPATIAL_RES;

                % FIX #2: controlla che il segnale non sia degenere (costante) dopo shift+crop
                Hist(h).Valid = true;
                if ~isempty(ref_sensor) && isfield(curr_signals.Filt, ref_sensor)
                    check_sig = double(curr_signals.Filt.(ref_sensor));
                    if length(check_sig) > 1 && std(check_sig) < 0.01
                        Hist(h).Valid = false;
                    end
                end
                Hist(h).GeoShift = shift_m;
                Hist(h).OriginalPos = true_avg_pos; % coerente col Pass 2 (centro difetto)
                Hist(h).Amp  = peak_amp(curr_signals, win_final);  % picco istantaneo unificato (post-crop, tutti i sensori)
                Hist(h).Data = curr_signals;
            end

            % FIX #2: rimuovi le run con segnale degenere dalla History
            if isfield(Hist, 'Valid')
                valid_mask = [Hist.Valid];
                if any(~valid_mask)
                    fprintf('   -> %d run con segnale degenere rimosse (shift eccessivo).\n', sum(~valid_mask));
                end
                Hist = Hist(valid_mask);
                Hist = rmfield(Hist, 'Valid');
                MASTER_DB(db_idx).Num_Occurrences = length(Hist);
            end

            % --- TETTO MASSIMO RUN PER GIUNTO ---
            if CFG.ONLY_JOINTS && numel(Hist) > CFG.JOINT_MAX_RUNS
                [~, ord_d] = sort([Hist.Date], 'descend');   % tieni le più recenti
                Hist = Hist(ord_d(1:CFG.JOINT_MAX_RUNS));
                [~, ord_a] = sort([Hist.Date], 'ascend');    % ripristina cronologico
                Hist = Hist(ord_a);
            end
            MASTER_DB(db_idx).Num_Occurrences = numel(Hist);
            if ~isempty(Hist), MASTER_DB(db_idx).Max_Severity = max([Hist.Amp]); end
            MASTER_DB(db_idx).History         = Hist;
            MASTER_DB(db_idx).Num_Total_Runs  = numel(Hist);
            db_idx = db_idx + 1;
        end

        % =================================================================
        % SECONDO PASSAGGIO: COMPLETAMENTO DIFETTI CONFERMATI (Ultime 150 run)
        % =================================================================
        n_total_valid = sum([RunInfo.Valid]);
        
        for d = 1:length(MASTER_DB)
            if CFG.ONLY_JOINTS, break; end   % Pass 1 ha già estratto tutte le run sui giunti

            if MASTER_DB(d).Num_Occurrences < CFG.MIN_RUNS_COMPLETE
                continue;
            end
            
            defect_pos = MASTER_DB(d).Avg_Pos;
            OldHistory = MASTER_DB(d).History;
            existing_runs = string({OldHistory.RunName});
            
            fprintf('   [COMPLETAMENTO] Difetto PK %s (%d run rilevate)...\n', ...
                MASTER_DB(d).ID_PK, length(existing_runs));
            
            % Recuperiamo il master per il micro-allineamento
            [~, m_idx] = max([OldHistory.Amp]);
            MasterData = OldHistory(m_idx).Data;
            
            m_avail_sensors = fieldnames(MasterData.Filt);
            m_ref_sensor = '';
            m_max_energy = -1;
            for s = 1:length(m_avail_sensors)
                e = sum(double(MasterData.Filt.(m_avail_sensors{s})).^2);
                if e > m_max_energy
                    m_max_energy = e;
                    m_ref_sensor = m_avail_sensors{s};
                end
            end
            if ~isempty(m_ref_sensor)
                MasterFilt_C = double(MasterData.Filt.(m_ref_sensor));
            else
                MasterFilt_C = [];
            end
            
            % -----------------------------------------------------------------
            % NUOVA LOGICA: Ordina TUTTE le run valide dalla più recente alla più vecchia
            % -----------------------------------------------------------------
            valid_idx = find([RunInfo.Valid]);
            [~, date_order] = sort([RunInfo(valid_idx).Date], 'descend'); % Ordine cronologico inverso!
            sorted_run_idx = valid_idx(date_order);
            
            % Preallochiamo la nuova History che conterrà esattamente le ultime 150 run
            % NB: stesso ordine e stessi campi di OldHistory per permettere l'assegnazione diretta
            NewHistory = struct('Date', {}, 'Amp', {}, 'RunName', {}, 'Detected', {}, 'MacroShift', {}, 'GeoShift', {}, 'OriginalPos', {}, 'Data', {});
            
            filled = 0;
            added_no_trigger = 0;

            for ii = 1:length(sorted_run_idx)
                % Interrompiamo il ciclo appena raggiungiamo il limite massimo (150)
                if filled >= CFG.MAX_TOTAL_RUNS
                    break;
                end
                
                i = sorted_run_idx(ii);
                curr_run_name = string(RunInfo(i).RunName);
                
                % Controlla se questa run era già stata salvata nel 1° passaggio
                idx_in_old = find(existing_runs == curr_run_name, 1);
                
                if ~isempty(idx_in_old)
                    % RUN GIÀ TRIGGERATA: La copiamo mantenendo i dati già processati
                    filled = filled + 1;
                    NewHistory(filled) = OldHistory(idx_in_old);
                else
                    % RUN NON TRIGGERATA: La estraiamo, la allineiamo e la aggiungiamo
                    try
                        ds = CachedData{i};
                        if isempty(ds) || isempty(fieldnames(ds)), continue; end

                        ext_signals = extract_at_position(ds, defect_pos, CFG, fmin, fmax);
                        if isempty(ext_signals), continue; end

                        % --- Filtro Velocità ---
                        curr_speed = ext_signals.Speed;
                        target_speed = MASTER_DB(d).Mode_Speed;
                        if isnan(curr_speed) || curr_speed <= 0 || abs(curr_speed - target_speed) > CFG.SPEED_TOL
                            continue;
                        end

                        % --- Micro-allineamento via xcorr su envelope di Hilbert ---
                        shift_m = 0;
                        if ~isempty(MasterFilt_C) && ~isempty(m_ref_sensor) && isfield(ext_signals.Filt, m_ref_sensor)
                            CurrFilt_C = double(ext_signals.Filt.(m_ref_sensor));

                            [~, mast_zero_idx] = min(abs(MasterData.RelativeAxis));
                            [~, curr_zero_idx] = min(abs(ext_signals.RelativeAxis));

                            corr_radius_samp = round(CFG.ALIGN_FOCUS / CFG.SPATIAL_RES);

                            m_start = max(1, mast_zero_idx - corr_radius_samp);
                            m_end   = min(length(MasterFilt_C), mast_zero_idx + corr_radius_samp);
                            Master_Focus = MasterFilt_C(m_start:m_end);

                            c_start = max(1, curr_zero_idx - corr_radius_samp);
                            c_end   = min(length(CurrFilt_C), curr_zero_idx + corr_radius_samp);
                            Curr_Focus = CurrFilt_C(c_start:c_end);

                            max_lag_samples = round(CFG.ALIGN_MAX_LAG / CFG.SPATIAL_RES);
                            min_focus_len = min(length(Master_Focus), length(Curr_Focus));

                            if min_focus_len > max_lag_samples * 2
                                N_up = min_focus_len * CFG.UPSAMPLE_FACTOR;
                                Master_Up = interpft(Master_Focus(1:min_focus_len), N_up);
                                Curr_Up   = interpft(Curr_Focus(1:min_focus_len), N_up);

                                Env_Master = abs(hilbert(Master_Up));
                                Env_Curr   = abs(hilbert(Curr_Up));

                                max_lag_up = max_lag_samples * CFG.UPSAMPLE_FACTOR;
                                [corr_vals, lags] = xcorr(Env_Master, Env_Curr, max_lag_up);
                                [~, max_c_idx] = max(corr_vals);

                                shift_m = (lags(max_c_idx) / CFG.UPSAMPLE_FACTOR) * CFG.SPATIAL_RES;
                            end
                        end
                        
                        % --- Applica Shift ---
                        if shift_m ~= 0
                            for s = 1:length(m_avail_sensors)
                                sn = m_avail_sensors{s};
                                if isfield(ext_signals.Filt, sn)
                                    ext_signals.Filt.(sn) = shift_signal_frac(ext_signals.Filt.(sn), shift_m, CFG.SPATIAL_RES);
                                end
                            end
                            if isfield(ext_signals, 'Raw')
                                raw_sens = fieldnames(ext_signals.Raw);
                                for r_idx = 1:length(raw_sens)
                                    rsn = raw_sens{r_idx};
                                    if isfield(ext_signals.Raw, rsn)
                                        ext_signals.Raw.(rsn) = shift_signal_frac(ext_signals.Raw.(rsn), shift_m, CFG.SPATIAL_RES);
                                    end
                                end
                            end
                        end
                        
                        % --- Crop Finale ---
                        if CFG.ONLY_JOINTS, win_final = CFG.JOINT_WINDOW; else, win_final = CFG.WINDOW_FINAL; end
                        N_half = round(win_final / CFG.SPATIAL_RES);

                        center_crop_idx = round(length(ext_signals.RelativeAxis) / 2);
                        safe_start = max(1, center_crop_idx - N_half);
                        safe_end   = min(length(ext_signals.RelativeAxis), center_crop_idx + N_half);
                        
                        for s = 1:length(m_avail_sensors)
                            sn = m_avail_sensors{s};
                            if isfield(ext_signals.Filt, sn) && length(ext_signals.Filt.(sn)) > 1
                                ext_signals.Filt.(sn) = ext_signals.Filt.(sn)(safe_start:safe_end);
                            end
                        end
                        if isfield(ext_signals, 'Raw')
                            raw_sens = fieldnames(ext_signals.Raw);
                            for r_idx = 1:length(raw_sens)
                                rsn = raw_sens{r_idx};
                                if isfield(ext_signals.Raw, rsn) && length(ext_signals.Raw.(rsn)) > 1
                                    ext_signals.Raw.(rsn) = ext_signals.Raw.(rsn)(safe_start:safe_end);
                                end
                            end
                        end
                        idx_vector = (safe_start:safe_end)' - center_crop_idx;
                        ext_signals.RelativeAxis = idx_vector * CFG.SPATIAL_RES;
                        
                        % --- Calcola Data Esatta ---
                        exact_date = RunInfo(i).Date;
                        if isfield(ds, 'time') && ~isempty(ds.time)
                            time_array = RunInfo(i).Date + seconds(double(ds.time));
                            [~, idx_closest] = min(abs(double(ds.space_neutral) - defect_pos));
                            exact_date = time_array(idx_closest);
                        end
                        
                        % --- Calcola Amp locale (picco istantaneo unificato) ---
                        local_amp = peak_amp(ext_signals, win_final);
                        
                        % --- Aggiunge a NewHistory ---
                        filled = filled + 1;
                        added_no_trigger = added_no_trigger + 1;
                        
                        NewHistory(filled).Date     = exact_date;
                        NewHistory(filled).Amp      = local_amp;
                        NewHistory(filled).RunName  = RunInfo(i).RunName;
                        NewHistory(filled).Detected = false; % <--- Nessun trigger
                        NewHistory(filled).GeoShift = shift_m;
                        NewHistory(filled).MacroShift = RunInfo(i).GeoShift;
                        NewHistory(filled).OriginalPos = defect_pos; % <--- NEL PASS 2 ERA IL CENTRO DEL CLUSTER
                        NewHistory(filled).Data     = ext_signals;
                        
                    catch ME_fill
                        fprintf('      [WARN] File %s: %s\n', RunInfo(i).RunName, ME_fill.message);
                    end
                end
            end
            
            % Sostituiamo la vecchia History con la nuova (che ora è ordinata e limitata a 150)
            MASTER_DB(d).History = NewHistory;
            MASTER_DB(d).Num_Total_Runs = length(NewHistory);
            
            fprintf('      -> Storia aggiornata: %d run in ordine cronologico inverso (di cui %d aggiunte ora).\n', ...
                MASTER_DB(d).Num_Total_Runs, added_no_trigger);
        end
        % =================================================================
        % FINE SECONDO PASSAGGIO
        % =================================================================
        save(fullfile(CFG.save_folder, ['Database_damage_' curr_route_name '.mat']), 'MASTER_DB');
    end
end

% =========================================================================
% FUNZIONI
% =========================================================================
function [Events] = analyze_and_extract(data, C, fmin, fmax)
    Events = struct('Pos', {}, 'Amp', {}, 'Signals', {});
    
    fs_time = 1000; 
    space_raw = double(data.space_neutral);
    
    % --- Gestione Assi ---
    if isfield(data, 'space_front') && isfield(data, 'space_back')
        axis_F = double(data.space_front); 
        axis_R = double(data.space_back);
    elseif isfield(data, 'space_parameters')
        pF = 0; pR = 0;
        if isfield(data.space_parameters, 'front'), pF = data.space_parameters.front; end
        if isfield(data.space_parameters, 'back'),  pR = data.space_parameters.back; end
        axis_F = space_raw + pF; 
        axis_R = space_raw + pR;
    else
        axis_F = space_raw; 
        axis_R = space_raw;
    end

    common_space_axis = (ceil(min(space_raw)/C.SPATIAL_RES) : floor(max(space_raw)/C.SPATIAL_RES)) * C.SPATIAL_RES;
    fs_space_res = 1/C.SPATIAL_RES;
    
    % --- DEFINIZIONE SENSORI ---
    AxialNames = {'left_sensor_front', 'left_sensor_rear', ...
                  'right_sensor_front', 'right_sensor_rear'};
    
    LateralNames = {'right_sensor_front_lat', 'right_sensor_rear_lat', ...
                    'left_sensor_front_lat', 'left_sensor_rear_lat'};
    
    LateralPresent = {};
    for i = 1:length(LateralNames)
        if isfield(data, LateralNames{i})
            LateralPresent{end+1} = LateralNames{i}; %#ok<AGROW>
        end
    end
    
    TechNames = [AxialNames, LateralPresent];
    
    Res_Sigs = struct(); Raw_Sigs = struct(); det_locs = [];

    % --- MASCHERA SWITCH: campioni dentro i range degli scambi (detection OFF) ---
    % data.switch.location e' gia' nel frame shiftato (sommato nel main loop),
    % quindi allineato a common_space_axis. Coppie (a,b) -> zona [a-1, b+1] m.
    switch_mask = false(size(common_space_axis));
    if C.FILTER_SWITCHES && isfield(data, 'switch') && isfield(data.switch, 'location') ...
            && ~isempty(data.switch.location)
        sw_loc  = double(data.switch.location(:));
        n_pairs = floor(numel(sw_loc) / 2);
        for sp = 1:n_pairs
            lo = sw_loc(2*sp-1) - 1;
            hi = sw_loc(2*sp)   + 1;
            switch_mask = switch_mask | (common_space_axis >= lo & common_space_axis <= hi);
        end
    end
    % Campioni da TENERE: gli switch sono rimossi (i due lati diventano contigui)
    keep_det = ~switch_mask;
    axis_det = common_space_axis(keep_det);
  % --- ELABORAZIONE E DETECTION (TRIGGER) ---
    
    % --- SPOSTAMENTO FILTRI FUORI DAL CICLO ---
    [bT, aT] = butter(2, [fmin, fmax]/(fs_time/2), 'bandpass');
    [bQ, aQ] = butter(2, [1/C.L_MAX, 1/C.L_MIN_QUIET]/(fs_space_res/2), 'bandpass');
    
    for i = 1:length(TechNames)
        nm = TechNames{i};
        
        sig = double(data.(nm));
        L = min([length(sig), length(space_raw)]);
        
        sig_raw = sig(1:L);
        
        cur_ax = axis_R(1:L); if contains(nm, 'front'), cur_ax = axis_F(1:L); end
        [ax_u, idx_u] = unique(cur_ax, 'stable');
        
        % --- RAW EFFETTIVO: solo ricampionamento spaziale, NESSUN filtro ---
        % DC preservato. Per togliere solo l'offset costante decommenta:
        % sig_raw = sig_raw - mean(sig_raw, 'omitnan');
        Raw_Sigs.(nm) = interp1(ax_u, sig_raw(idx_u), common_space_axis, 'linear', 0);
        
        % --- FILT: pipeline INVARIATA ---
        sig_dem = sig_raw - mean(sig_raw, 'omitnan');
        sig_t   = filtfilt(bT, aT, sig_dem);
        sig_sp  = interp1(ax_u, sig_t(idx_u), common_space_axis, 'linear', 0);
        sig_f   = filtfilt(bQ, aQ, sig_sp);

        Res_Sigs.(nm) = sig_f;
        
        % Detection: switch TAGLIATI (campioni rimossi via keep_det)
        sig_det = sig_f(keep_det);

        N_f = round(C.RMS_WIN_FAST/C.SPATIAL_RES);
        env = sqrt(movmean(sig_det.^2, N_f));
        
        th_bkg = movmean(env, round(C.RMS_WIN_SLOW/C.SPATIAL_RES));
        th_dynamic = max(th_bkg * C.RMS_MUL, 0.05);
        
        [pks, locs] = findpeaks(env, 'MinPeakDistance', round(C.MIN_DIST/C.SPATIAL_RES));
        
        if ~isempty(locs)
            valid = pks > th_dynamic(locs) & pks > C.ABS_RMS_THRESH;
            valid_locs = locs(valid);
            
            % --- NUOVO: RAFFINAMENTO DEL PICCO ---
            % L'RMS può essere sfasato. Cerchiamo il vero picco del segnale
            % filtrato in un raggio di 5 metri attorno al trigger RMS.
            search_radius = round(5.0 / C.SPATIAL_RES);
            refined_locs = valid_locs;
            
            for idx = 1:length(valid_locs)
                c_loc = valid_locs(idx);
                start_idx = max(1, c_loc - search_radius);
                end_idx   = min(length(sig_det), c_loc + search_radius);
                % Trova l'indice del massimo assoluto nel segnale reale
                [~, max_local_idx] = max(abs(sig_det(start_idx:end_idx)));
                refined_locs(idx) = start_idx + max_local_idx - 1;
            end
            
            % Aggiorna locs e pks con i valori corretti centrati sul picco vero
            if any(valid)
                det_locs = [det_locs; axis_det(refined_locs)', abs(sig_det(refined_locs))'];
            end
        end
    end
    
    if isempty(det_locs), return; end
    
    % --- MERGING ---
    det_locs = sortrows(det_locs, 1);
    merged = [];
    if ~isempty(det_locs)
        cp = det_locs(1,1); ma = det_locs(1,2);
        for i=2:size(det_locs,1)
            if det_locs(i,1)-cp <= C.CROSS_TOL
                if det_locs(i,2)>ma, ma=det_locs(i,2); cp=det_locs(i,1); end
            else
                merged=[merged; cp, ma]; cp=det_locs(i,1); ma=det_locs(i,2); %#ok<AGROW>
            end
        end
        merged=[merged; cp, ma]; %#ok<AGROW>
    end
    
    % --- FILTRO BORDI ---
    if ~isempty(merged)
        min_safe_pos = min(common_space_axis) + C.WINDOW_EXTRACT;
        max_safe_pos = max(common_space_axis) - C.WINDOW_EXTRACT;
        valid_mask = (merged(:,1) >= min_safe_pos) & (merged(:,1) <= max_safe_pos);
        merged = merged(valid_mask, :);
    end
    
    if isempty(merged), return; end

    % --- ESTRAZIONE DATI ---
    AllLateralNames = {'right_sensor_front_lat', 'right_sensor_rear_lat', ...
                       'left_sensor_front_lat', 'left_sensor_rear_lat'};
    
    for k = 1:size(merged, 1)
        c_pos = merged(k,1);
        Events(k).Pos = c_pos;
        Events(k).Amp = merged(k,2); 
        
        idx_win = common_space_axis >= (c_pos - C.WINDOW_EXTRACT) & ...
              common_space_axis <= (c_pos + C.WINDOW_EXTRACT);

        Events(k).Signals.RelativeAxis = common_space_axis(idx_win) - c_pos;

        idx_raw = space_raw >= (c_pos - C.WINDOW_EXTRACT) & space_raw <= (c_pos + C.WINDOW_EXTRACT);

        if isfield(data, 'speed_kmh')
            Events(k).Signals.Speed = single(mean(double(data.speed_kmh(idx_raw)), 'omitnan'));
        elseif isfield(data, 'speed')
            Events(k).Signals.Speed = single(mean(double(data.speed(idx_raw)), 'omitnan'));
        else
            Events(k).Signals.Speed = single(0);
        end
        
        if isfield(data, 'curve')
            Events(k).Signals.Curve = single(mean(abs(double(data.curve(idx_raw))), 'omitnan'));
        else
            Events(k).Signals.Curve = single(0);
        end

        for s = 1:length(AxialNames)
            nm = AxialNames{s};
            if isfield(Res_Sigs, nm)
                Events(k).Signals.Filt.(nm) = single(Res_Sigs.(nm)(idx_win));
            end
            if C.SAVE_RAW && isfield(Raw_Sigs, nm)
                Events(k).Signals.Raw.(nm) = single(Raw_Sigs.(nm)(idx_win)); 
            end
        end
        
        for s = 1:length(AllLateralNames)
            nm = AllLateralNames{s};
            if isfield(Res_Sigs, nm)
                Events(k).Signals.Filt.(nm) = single(Res_Sigs.(nm)(idx_win));
                if C.SAVE_RAW && isfield(Raw_Sigs, nm)
                    Events(k).Signals.Raw.(nm) = single(Raw_Sigs.(nm)(idx_win));
                end
            else
                Events(k).Signals.Filt.(nm) = single(0);
                if C.SAVE_RAW
                    Events(k).Signals.Raw.(nm) = single(0);
                end
            end
        end
    end
end


% =========================================================================
% EXTRACT_AT_POSITION - Estrae i segnali in una posizione nota senza detection
% Stessa pipeline di filtraggio di analyze_and_extract, ma senza trigger.
% =========================================================================
% =========================================================================
% EXTRACT_AT_POSITION - Estrae i segnali in una posizione nota senza detection
% OTTIMIZZATA: Taglia il segnale grezzo prima di filtrare per velocizzare!
% =========================================================================
function signals = extract_at_position(data, target_pos, C, fmin, fmax)
    signals = [];
    
    fs_time = 1000;
    space_raw = double(data.space_neutral);
    
    % Verifica che la posizione sia coperta dai dati
    if target_pos < min(space_raw) + C.WINDOW_EXTRACT || ...
       target_pos > max(space_raw) - C.WINDOW_EXTRACT
        return;
    end
    
    % --- Gestione Assi ---
    if isfield(data, 'space_front') && isfield(data, 'space_back')
        axis_F = double(data.space_front); 
        axis_R = double(data.space_back);
    elseif isfield(data, 'space_parameters')
        pF = 0; pR = 0;
        if isfield(data.space_parameters, 'front'), pF = data.space_parameters.front; end
        if isfield(data.space_parameters, 'back'),  pR = data.space_parameters.back; end
        axis_F = space_raw + pF; 
        axis_R = space_raw + pR;
    else
        axis_F = space_raw; 
        axis_R = space_raw;
    end

    fs_space_res = 1/C.SPATIAL_RES;
    
    % --- Sensori ---
    AxialNames = {'left_sensor_front', 'left_sensor_rear', ...
                  'right_sensor_front', 'right_sensor_rear'};
    AllLateralNames = {'right_sensor_front_lat', 'right_sensor_rear_lat', ...
                       'left_sensor_front_lat', 'left_sensor_rear_lat'};
    
    LateralPresent = {};
    for i = 1:length(AllLateralNames)
        if isfield(data, AllLateralNames{i})
            LateralPresent{end+1} = AllLateralNames{i}; %#ok<AGROW>
        end
    end
    TechNames = [AxialNames, LateralPresent];
    
    % =========================================================
    % IL TRUCCO: PRE-CROP. Tagliamo il segnale grezzo PRIMA 
    % di filtrare. Aggiungiamo il margine per far sfogare i filtri.
    % =========================================================
    idx_raw_wide = space_raw >= (target_pos - C.WINDOW_EXTRACT - C.FILTER_MARGIN) & ...
                   space_raw <= (target_pos + C.WINDOW_EXTRACT + C.FILTER_MARGIN);
    
    if sum(idx_raw_wide) < 100, return; end
    
    % Assi e segnali ridotti solo all'area di interesse!
    space_raw_crop = space_raw(idx_raw_wide);
    axis_F_crop    = axis_F(idx_raw_wide);
    axis_R_crop    = axis_R(idx_raw_wide);
    
   % Fase assoluta (multipli di RES): identica a common_space_axis del Pass 1 e all'app
    common_space_axis_crop = (ceil(min(space_raw_crop)/C.SPATIAL_RES) : floor(max(space_raw_crop)/C.SPATIAL_RES)) * C.SPATIAL_RES;
    % --- Filtraggio sul pezzetto ---
    Res_Sigs = struct(); Raw_Sigs = struct();
    [bT, aT] = butter(2, [fmin, fmax]/(fs_time/2), 'bandpass');
    [bQ, aQ] = butter(2, [1/C.L_MAX, 1/C.L_MIN_QUIET]/(fs_space_res/2), 'bandpass');
    
    for i = 1:length(TechNames)
        nm = TechNames{i};
        sig = double(data.(nm));
        sig_crop = sig(idx_raw_wide); % Prendo solo il pezzetto!
        
        cur_ax = axis_R_crop; if contains(nm, 'front'), cur_ax = axis_F_crop; end
        [ax_u, idx_u] = unique(cur_ax, 'stable');
        
        % --- RAW EFFETTIVO: solo ricampionamento spaziale, NESSUN filtro ---
        % DC preservato. Per togliere solo l'offset costante decommenta:
        % sig_crop = sig_crop - mean(sig_crop, 'omitnan');
        Raw_Sigs.(nm) = interp1(ax_u, sig_crop(idx_u), common_space_axis_crop, 'linear', 0);
        
        % --- FILT: pipeline INVARIATA ---
        sig_dem = sig_crop - mean(sig_crop, 'omitnan');
        sig_t   = filtfilt(bT, aT, sig_dem);
        sig_sp  = interp1(ax_u, sig_t(idx_u), common_space_axis_crop, 'linear', 0);
        sig_f   = filtfilt(bQ, aQ, sig_sp);
        Res_Sigs.(nm) = sig_f;
    end
    
    % --- Estrazione finestra esatta finale ---
    idx_win = common_space_axis_crop >= (target_pos - C.WINDOW_EXTRACT) & ...
              common_space_axis_crop <= (target_pos + C.WINDOW_EXTRACT);
    
    if sum(idx_win) < 10, return; end
    
    signals.RelativeAxis = common_space_axis_crop(idx_win) - target_pos;
    
    % Finestra stretta per calcolare velocità e curva
    idx_raw_exact = space_raw >= (target_pos - C.WINDOW_EXTRACT) & ...
                    space_raw <= (target_pos + C.WINDOW_EXTRACT);
    
    if isfield(data, 'speed_kmh')
        signals.Speed = single(mean(double(data.speed_kmh(idx_raw_exact)), 'omitnan'));
    elseif isfield(data, 'speed')
        signals.Speed = single(mean(double(data.speed(idx_raw_exact)), 'omitnan'));
    else
        signals.Speed = single(0);
    end
    
    if isfield(data, 'curve')
        signals.Curve = single(mean(abs(double(data.curve(idx_raw_exact))), 'omitnan'));
    else
        signals.Curve = single(0);
    end
    
    % Assegnazione Verticali
    for s = 1:length(AxialNames)
        nm = AxialNames{s};
        if isfield(Res_Sigs, nm)
            signals.Filt.(nm) = single(Res_Sigs.(nm)(idx_win));
        end
        if C.SAVE_RAW && isfield(Raw_Sigs, nm)
            signals.Raw.(nm) = single(Raw_Sigs.(nm)(idx_win));
        end
    end
    
    % Assegnazione Laterali
    for s = 1:length(AllLateralNames)
        nm = AllLateralNames{s};
        if isfield(Res_Sigs, nm)
            signals.Filt.(nm) = single(Res_Sigs.(nm)(idx_win));
            if C.SAVE_RAW && isfield(Raw_Sigs, nm)
                signals.Raw.(nm) = single(Raw_Sigs.(nm)(idx_win));
            end
        else
            signals.Filt.(nm) = single(0);
            if C.SAVE_RAW
                signals.Raw.(nm) = single(0);
            end
        end
    end
end

function dati = load_infrastructure_map(file, type)
    sh = {'1 d','1 dd'}; if strcmpi(type,'pari'), sh = {'1 p','1 dp'}; end
    dati = table();
    for i=1:length(sh)
        try
            r = readcell(file, 'Sheet', sh{i});
            for j=3:size(r,1)
                p1 = r{j,20}; p2 = r{j,21};
                if isnumeric(p1) && isnumeric(p2) && (p1+p2)>0
                    dati = [dati; table(sh(i), "Elemento", p1, p2, string(r{j,1})+" "+string(r{j,13}), ...
                        'VariableNames', {'Foglio','Tipo','Pk_Inizio','Pk_Fine','Descrizione'})]; %#ok<AGROW>
                end
            end
        catch, continue; end
    end
end

% 
% function shifted_sig = shift_signal_frac(sig, shift_m, spatial_res)
% % SHIFT_SIGNAL_FRAC: Micro-shift via interpolazione Spline (Sub-campione ultra-veloce)
% 
%     N = length(sig);
%     if N <= 1, shifted_sig = sig; return; end
% 
%     is_row = isrow(sig);
%     is_single = isa(sig, 'single');
%     sig = double(sig(:));
% 
%     % Creiamo l'asse spaziale originale
%     x = (0:N-1)' * spatial_res;
% 
%     % Applichiamo il micro-shift continuo usando la curva Spline.
%     % Mettiamo '0' alla fine per azzerare i valori che "escono" dai bordi.
%     shifted_sig = interp1(x, sig, x - shift_m, '*spline', 0);
% 
%     if is_single
%         shifted_sig = single(shifted_sig);
%     end
% 
%     if is_row
%         shifted_sig = shifted_sig';
%     end
% end

function shifted_sig = shift_signal_frac(sig, shift_m, spatial_res)
% SHIFT_SIGNAL_FRAC: Micro-shift via Fase FFT (Preserva forma e ampiezza!)
    N = length(sig);
    if N <= 1, shifted_sig = sig; return; end
    
    is_row = isrow(sig);
    is_single = isa(sig, 'single');
    sig = double(sig(:));
    
    % Calcolo dello shift in numero di campioni
    shift_samples = shift_m / spatial_res;
    
    % Trasformata di Fourier
    X = fft(sig);
    
    % Vettore delle frequenze
    k = (0:N-1)';
    half_N = floor(N/2);
    k(k > half_N) = k(k > half_N) - N; 
    
    % Shift di fase: moltiplico per e^(-j*2*pi*k*shift/N)
    phase_shift = exp(-1i * 2 * pi * k * shift_samples / N);
    X_shifted = X .* phase_shift;
    
    % Ritorno al dominio spaziale
    shifted_sig = real(ifft(X_shifted));
    
    if is_single, shifted_sig = single(shifted_sig); end
    if is_row, shifted_sig = shifted_sig'; end
end


function a = peak_amp(sig, half_w)
% Picco istantaneo unificato: max(|filtrato|) su TUTTI i sensori,
% entro +/- half_w metri dal centro (RelativeAxis = 0).
    a = 0;
    if ~isstruct(sig) || ~isfield(sig, 'Filt'), return; end
    if isfield(sig, 'RelativeAxis') && ~isempty(sig.RelativeAxis)
        in_win = abs(double(sig.RelativeAxis)) <= half_w;
    else
        in_win = [];   % fallback: tutta la finestra
    end
    fn = fieldnames(sig.Filt);
    for k = 1:numel(fn)
        v = double(sig.Filt.(fn{k}));
        if numel(v) > 1
            if isempty(in_win)
                vv = v;
            else
                m = min(numel(v), numel(in_win));
                vv = v(in_win(1:m));
            end
            if ~isempty(vv), a = max(a, max(abs(vv))); end
        end
    end
end

function Events = extract_at_joints(data, joint_pos, joint_labels, C, fmin, fmax)
% Estrazione forzata sui giunti: nessun trigger. Per ogni giunto chiama
% extract_at_position con finestra dedicata e calcola un'ampiezza locale.
    Events = struct('Pos', {}, 'Amp', {}, 'Signals', {}, 'Label', {});
    if isempty(joint_pos), return; end

    % Estraggo più largo di JOINT_WINDOW per lasciare spazio al micro-allineamento;
    % il crop finale userà JOINT_WINDOW.
    Cj = C;
    Cj.WINDOW_EXTRACT = C.JOINT_WINDOW + C.ALIGN_MAX_LAG + 1.0;

    n = 0;
    for j = 1:numel(joint_pos)
        sig = extract_at_position(data, joint_pos(j), Cj, fmin, fmax);
        if isempty(sig), continue; end   % giunto fuori copertura in questa run

        % Picco istantaneo entro +/- JOINT_WINDOW (stessa metrica unificata)
        amp = peak_amp(sig, C.JOINT_WINDOW);

        n = n + 1;
        Events(n).Pos     = joint_pos(j);
        Events(n).Amp     = amp;
        Events(n).Signals = sig;
        if j <= numel(joint_labels)
            Events(n).Label = joint_labels(j);
        else
            Events(n).Label = string(j);
        end
    end
end

function J = load_joints_map(file, type)
% Legge Position-Giunti.xlsx -> tabella Stations, Position (m assoluti), Joint, Shared.
% Legge i fogli il cui nome contiene 'type' (es. 'pari' -> M1-Pari, M2-Pari);
% il filtro per tratta (Stations) disambigua poi M1 da M2.
    J = table();
    try, sheets = string(sheetnames(file)); catch, [~, s] = xlsfinfo(file); sheets = string(s); end
    for s = 1:numel(sheets)
        sh = sheets(s);
        if ~isempty(type) && ~contains(lower(sh), lower(string(type))), continue; end
        try, r = readcell(file, 'Sheet', char(sh)); catch, continue; end
        if size(r,1) < 2, continue; end

        hdr = strtrim(lower(string(r(1,:))));
        c_sta = find(contains(hdr, 'station'), 1);
        c_jnt = find(contains(hdr, 'joint'),   1);
        c_shr = find(contains(hdr, 'shared'),  1);
        c_pos = find(contains(hdr, 'fixed'),   1);          % M1: posizione assoluta
        if isempty(c_pos), c_pos = find(contains(hdr, 'position'), 1); end  % M2
        if isempty(c_sta) || isempty(c_pos), continue; end

        for j = 2:size(r,1)
            pos = to_num(r{j, c_pos});
            if isnan(pos), continue; end
            sta = string(r{j, c_sta});
            jnt = ""; if ~isempty(c_jnt), jnt = string(r{j, c_jnt}); end
            shr = ""; if ~isempty(c_shr), shr = string(r{j, c_shr}); end
            J = [J; table(sta, pos, jnt, shr, ...
                'VariableNames', {'Stations','Position','Joint','Shared'})]; %#ok<AGROW>
        end
    end
end
function Env_Template = build_align_template(sorted_s, ref_sensor, focus_len, max_lag_samples, N_up, C)
% Riferimento di allineamento robusto: envelope media iterata, upsamplata a N_up,
% centrata sul proprio picco. Costruita a risoluzione nativa (economica).
    Env_Template = [];
    if isempty(ref_sensor) || focus_len < 3, return; end
    corr_radius_samp = (focus_len - 1) / 2;

    % 1) Envelope di focus (risoluzione nativa) per ogni run valida
    R = height(sorted_s);
    E = zeros(focus_len, R);
    valid = false(1, R);
    for h = 1:R
        sg = sorted_s.Signals(h);
        if ~isfield(sg.Filt, ref_sensor), continue; end
        f = double(sg.Filt.(ref_sensor));
        [~, z] = min(abs(sg.RelativeAxis));
        a = z - corr_radius_samp; b = z + corr_radius_samp;
        if a < 1 || b > length(f), continue; end
        e = abs(hilbert(f(a:b)));
        if std(e) < 1e-9, continue; end
        E(:, h) = e(:);
        valid(h) = true;
    end
    E = E(:, valid);
    if size(E, 2) < 2, return; end

    % 2) Seed = MEDOIDE: la run la cui envelope e' in media piu' correlata alle altre
    En = E ./ (sqrt(sum(E.^2, 1)) + eps);   % colonne a norma unitaria
    Cm = En' * En;                          % matrice di correlazione RxR
    score = (sum(Cm, 2) - 1) / (size(Cm, 2) - 1);
    [~, seed] = max(score);
    ref = E(:, seed);

    % 2b) (opzionale) usa solo le N run piu' simili al medoide per la media
    cols = 1:size(E, 2);
    if isfield(C, 'ALIGN_TEMPLATE_NRUNS') && C.ALIGN_TEMPLATE_NRUNS > 0 ...
            && C.ALIGN_TEMPLATE_NRUNS < numel(cols)
        [~, ord] = sort(Cm(:, seed), 'descend');
        cols = ord(1:C.ALIGN_TEMPLATE_NRUNS)';
    end

    % 3) Iterazioni: allinea le envelope al riferimento -> media -> ri-centra sul picco
    iters = 3;
    if isfield(C, 'ALIGN_TEMPLATE_ITERS'), iters = max(1, C.ALIGN_TEMPLATE_ITERS); end
    cF = corr_radius_samp + 1;              % indice del centro nominale
    for it = 1:iters
        acc = zeros(focus_len, 1);
        for jj = cols(:)'
            [cv, lg] = xcorr(ref, E(:, jj), max_lag_samples);
            [~, mi] = max(cv);
            acc = acc + shift_fill(E(:, jj), lg(mi));
        end
        ref = acc / numel(cols);
        [~, pk] = max(ref);
        ref = shift_fill(ref, cF - pk);
    end

    % 4) Upsample alla risoluzione del matching per-run
    Env_Template = interpft(ref, N_up);
    Env_Template = Env_Template(:);
end

function y = shift_fill(x, k)
% Shift intero con riempimento a zero (nessun wrap-around).
    x = x(:); n = numel(x); y = zeros(n, 1); k = round(k);
    if k >= 0
        if k < n, y(1+k:n) = x(1:n-k); end
    else
        k = -k;
        if k < n, y(1:n-k) = x(1+k:n); end
    end
end

function x = to_num(v)
    if isnumeric(v), x = double(v);
    elseif ischar(v) || isstring(v), x = str2double(v);
    else, x = NaN; end
end

tempo_totale = toc;
fprintf('Tempo totale di esecuzione: %.2f secondi\n', tempo_totale);