%% ULTIMATE INSPECTOR V10: FINAL CLEAN VERSION

% - Analisi Statistica Globale (Tutte le Run)
% - NO Cluster/Aree (Solo Scatter punti)
% - Selezione Gruppo (SX/DX) tramite menu in alto
% - Interattività (Click per PK)

clear; clc; close all;

% =========================================================================
% CONFIGURAZIONE PERCORSI (MODIFICA QUI)

% Assicurati che questo percorso sia ESATTAMENTE dove hai i file .mat originali
PARENT_FOLDER = 'C:\Users\Nicco\MATLAB Drive\TESI\M2_pari'; 
DB_FOLDER     = 'C:\Users\Nicco\MATLAB Drive\TESI\Defect_Database_pari';
EXCEL_PATH    = '';
% EXCEL_PATH    = 'C:\Users\Nicco\MATLAB Drive\TESI\M1-PEDRO.xlsx';
JOINTS_EXCEL_PATH = 'C:\Users\Nicco\MATLAB Drive\TESI\Position-Giunti.xlsx';

% =========================================================================
% INIZIALIZZAZIONE
% =========================================================================
if ~exist(PARENT_FOLDER, 'dir'), errordlg(['Cartella RAW non trovata: ' PARENT_FOLDER]); return; end
d = dir(PARENT_FOLDER); isSub = [d.isdir]; folderNames = {d(isSub).name};
TrackList = folderNames(~ismember(folderNames, {'.', '..'}));
if isempty(TrackList), errordlg('Nessuna cartella trovata.'); return; end

% --- Parametri Default ---
DefaultParams.L_Max      = 0.5; 
DefaultParams.L_Quiet    = 0.07;
DefaultParams.L_Stress   = 0.07;
DefaultParams.Win_Shock  = 1;   
DefaultParams.Win_Bkg    = 20.0;  
DefaultParams.K_Factor   = 3;   
DefaultParams.Ref_C      = 0.004;
DefaultParams.Ref_A      = 0.8;
DefaultParams.Min_Dist   = 1.0;
DefaultParams.Abs_Thresh = 5.0;
CFG.WINDOW_SIZE = 5.0;  % metri, uguale al database
CFG.L_MAX = 0.5;           
CFG.L_MIN_QUIET = 0.07;    
CFG.L_MIN_STRESS = 0.07;   
CFG.REF_C = 0.004;         
CFG.REF_A = 0.8; 
CFG.fs_time = 1000;        % 
CFG.fmin = 2;              % 
CFG.fmax = 350;            % 
CFG.RMS_WIN_FAST = 1.0;    %  (metri)
CFG.RMS_WIN_SLOW = 20.0;   %  (metri)
CFG.RMS_MUL = 3;         % 
CFG.ABS_RMS_THRESH = 5.0;  %
CFG.SPATIAL_RES = 0.030;   %
CFG.MIN_RUNS_TOP20 = 5;    % (legacy, non più usato — vedi IPI_MIN_RUNS)
CFG.IPI_MIN_RUNS   = 5;     % Soglia min. passaggi per calcolo IPI (leaderboard + Top-20)

% --- Parametri Indice Rischio Degrado (IPI) ---

CFG.IPI_RECENT_DAYS      = 30;   % Finestra "recente" fissa in giorni (era proporzionale)
CFG.IPI_MIN_HISTORY_DAYS = 45;   % Storia minima per calcolare trend (15 base + 30 recent)
CFG.IPI_MIN_DAYS     = 10;      % Giorni minimi di storico per calcolare l'IPI
%CFG.IPI_WIN_PERC     = 0.30;   % Finestra % (es. ultimo 15% dei passaggi) per calcolare il trend recente (legacy)
%CFG.IPI_WIN_MIN      = 3;      % Numero minimo di passaggi nelle finestre (Baseline/Recente) 
CFG.IPI_TREND_MAX    = 100;    % Punteggio massimo per il trend verticale
CFG.IPI_TREND_SENS   = 80;     % Sensibilità trend: +80% di incremento = 100 punti IPI
CFG.IPI_LAT_BONUS    = 30;     % Punteggio massimo aggravante laterale
CFG.IPI_LAT_THRESH   = 0.7;    % Soglia ratio Lat/Vert per dare il massimo bonus laterale
% --- Parametri PCA per IPI (nuovi) ---
CFG.IPI_PCA_BONUS       = 20;    % Max bonus IPI dal trend RMSE PCA
CFG.IPI_PCA_SENS        = 50;    % % aumento RMSE PCA per max bonus trend (50% → +20)
CFG.IPI_PCA_EXCUR_BONUS = 5;     % Max bonus per shock recenti (RMSE > μ+2σ)
CFG.IPI_PCA_EXCUR_DAYS  = 7;     % Finestra "ultima settimana" per excursioni
CFG.IPI_PCA_K           = 2;     % N. componenti PCA usate per residuo
CFG.IPI_PCA_MIN_RUNS    = 30;    % Min passaggi per direzione per costruire PCA

CFG.IPI_CREST_BONUS  = 10;     % Punteggio massimo aggravante forma (Crest Factor)
CFG.IPI_IA_BONUS     = 20;     % Punteggio massimo aggravante Intelligenza Artificiale
% --- Parametri Penalità Bassa Energia ---
CFG.IPI_SEV_PENALTY_MAX = 20;  % Massimo decremento punti
CFG.IPI_SEV_THR_LOW     = 15;  % Sotto i 15 m/s^2 -> -20 punti fissi
CFG.IPI_SEV_THR_HIGH    = 50;  % Sopra i 50 m/s^2 -> 0 punti (nessuna penalità)
% Mappa Sensori (Definizione Gruppi)
SensorsOrder = {
    'left_sensor_front',      'Vert SX (Front)';
    'left_sensor_rear',       'Vert SX (Rear)';
    'right_sensor_front',     'Vert DX (Front)';
    'right_sensor_rear',      'Vert DX (Rear)';
    'right_sensor_front_lat', 'Lat DX (Front)';
    'right_sensor_rear_lat',  'Lat DX (Rear)' ;
    'left_sensor_front_lat',  'Lat SX (Front)';
    'left_sensor_rear_lat',   'Lat SX (Rear)'
};


GroupList = {'Verticale SX', 'Verticale DX', 'Laterale DX', 'Laterale SX'};
GroupMap = containers.Map();
GroupMap('Verticale SX') = {'left_sensor_front', 'left_sensor_rear'};
GroupMap('Verticale DX') = {'right_sensor_front', 'right_sensor_rear'};
GroupMap('Laterale DX')  = {'right_sensor_front_lat', 'right_sensor_rear_lat'};
GroupMap('Laterale SX')  = {'left_sensor_front_lat','left_sensor_rear_lat'};


% =========================================================================
% INTERFACCIA GRAFICA (CLEAN & FULL WIDTH)
% =========================================================================
f = figure('Name', 'Beta Analisi Tratta', 'Color', 'w', 'WindowState', 'maximized');


% --- 1. BARRA NAVIGAZIONE ---
pnl_nav = uipanel('Parent', f, 'Position', [0.01 0.94 0.98 0.05], 'BackgroundColor', [0.94 0.94 0.94], 'BorderType', 'none');

% Selezione Tratta
uicontrol('Parent', pnl_nav, 'Style', 'text', 'String', 'TRATTA:', ...
    'Units', 'normalized', 'Position', [0.01 0.2 0.05 0.6], ...
    'BackgroundColor', [0.94 0.94 0.94], 'FontWeight', 'bold');

h_popup_track = uicontrol('Parent', pnl_nav, 'Style', 'popupmenu', 'String', TrackList, ...
    'Units', 'normalized', 'Position', [0.07 0.2 0.20 0.6], ...
    'Callback', @on_change_track);

% Selezione Gruppo (SX / DX)
uicontrol('Parent', pnl_nav, 'Style', 'text', 'String', 'GRUPPO SENSORI:', ...
    'Units', 'normalized', 'Position', [0.28 0.2 0.08 0.6], ...
    'BackgroundColor', [0.94 0.94 0.94], 'FontWeight', 'bold');

h_popup_group = uicontrol('Parent', pnl_nav, 'Style', 'popupmenu', 'String', GroupList, ...
    'Units', 'normalized', 'Position', [0.37 0.2 0.12 0.6], ...
    'Callback', @on_change_group);

% --- NUOVO FILTRO VISTA (Front/Rear) ---
uicontrol('Parent', pnl_nav, 'Style', 'text', 'String', 'VISTA:', ...
    'Units', 'normalized', 'Position', [0.50 0.2 0.04 0.6], ...
    'BackgroundColor', [0.94 0.94 0.94], 'FontWeight', 'bold');

h_popup_view = uicontrol('Parent', pnl_nav, 'Style', 'popupmenu', 'String', {'Entrambi', 'Solo Front', 'Solo Rear'}, ...
    'Units', 'normalized', 'Position', [0.54 0.2 0.08 0.6], ...
    'Callback', @on_change_view);

% --- ETICHETTA DI STATO (Spostata e ridimensionata) ---
h_status_lbl = uicontrol('Parent', pnl_nav, 'Style', 'text', 'String', 'Ready', ...
    'Units', 'normalized', 'Position', [0.63 0.2 0.35 0.6], ...
    'BackgroundColor', [0.94 0.94 0.94], 'HorizontalAlignment', 'left', 'FontAngle', 'italic');

% --- 2. GRAFICI SUPERIORI (ALLARGATI - NO TUNING) ---
pnl_top_left = uipanel('Parent', f, 'Position', [0.01 0.66 0.49 0.27], 'Title', 'Contesto (Dati Filtrati DB)', 'BackgroundColor', 'w');
ax_context = axes('Parent', pnl_top_left, 'Position', [0.08 0.20 0.90 0.70]); grid on;

pnl_top_right = uipanel('Parent', f, 'Position', [0.51 0.66 0.24 0.27], 'Title', 'Analisi RMS (Pre-calcolata)', 'BackgroundColor', 'w');
ax_cfar = axes('Parent', pnl_top_right, 'Position', [0.08 0.20 0.90 0.70]); grid on;

% NUOVO: lista giunti/difetti della tratta (da Excel), accanto all'RMS
pnl_joints = uipanel('Parent', f, 'Position', [0.76 0.66 0.23 0.27], 'Title', 'Giunti Tratta (Excel)', 'BackgroundColor', 'w');
h_list_joints = uicontrol('Parent', pnl_joints, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.04 0.04 0.92 0.92]);

%% --- 3. PANNELLO INFERIORE ---
grp_bot = uipanel('Parent', f, 'Position', [0.01 0.01 0.98 0.64], 'BorderType', 'none', 'BackgroundColor', 'w');

% --- Lista Difetti + Filtro n ---
pnl_defects = uipanel('Parent', grp_bot, 'Position', [0.0 0.0 0.18 1.0], 'Title', 'Lista Difetti (DB)', 'BackgroundColor', 'w');

uicontrol('Parent', pnl_defects, 'Style', 'text', 'String', 'Filtra n >', ...
    'Units', 'normalized', 'Position', [0.05 0.94 0.4 0.04], ...
    'BackgroundColor', 'w', 'HorizontalAlignment', 'left');

h_edit_n = uicontrol('Parent', pnl_defects, 'Style', 'edit', 'String', '50', ...
    'Units', 'normalized', 'Position', [0.5 0.94 0.4 0.04], ...
    'Callback', @on_change_n);  % solo re-filter, senza reload DB

uicontrol('Parent', pnl_defects, 'Style', 'text', 'String', 'Filtra Giorno:', ...
    'Units', 'normalized', 'Position', [0.05 0.89 0.9 0.04], ...
    'BackgroundColor', 'w', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

h_btn_date = uicontrol('Parent', pnl_defects, 'Style', 'pushbutton', ...
    'String', '📅  Tutti i Giorni', ...
    'Units', 'normalized', 'Position', [0.05 0.83 0.9 0.05], ...
    'BackgroundColor', [0.96 0.96 0.98], 'FontWeight', 'bold', ...
    'Callback', @(src,~) open_calendar_dialog(ancestor(src,'figure')));

h_list_defects = uicontrol('Parent', pnl_defects, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.05 0.25 0.9 0.57], ...
    'Callback', @on_select_defect);

% PULSANTI
% uicontrol('Parent', pnl_defects, 'Style', 'pushbutton', 'String', 'Analisi FFT e rapporti', ...
    % 'Units', 'normalized', 'Position', [0.05 0.16 0.9 0.06], ...
    % 'BackgroundColor', [0.9 0.8 1], 'FontWeight', 'bold', ...
    % 'Callback', @(src,~) generate_defect_classification_report(guidata(src).DB, guidata(src).CFG));
uicontrol('Parent', pnl_defects, 'Style', 'pushbutton', 'String', '🏆 GLOBAL TOP 20', ...
    'Units', 'normalized', 'Position', [0.05 0.16 0.9 0.06], ...
    'BackgroundColor', [0.9 0.8 1], 'FontWeight', 'bold', ...
    'Callback', @(src,~) open_top_20_dashboard(guidata(src)));

uicontrol('Parent', pnl_defects, 'Style', 'pushbutton', 'String', '📊 REPORT GLOBALE', ...
    'Units', 'normalized', 'Position', [0.05 0.09 0.9 0.06], ...
    'BackgroundColor', [0.8 0.9 1], 'FontWeight', 'bold', ...
    'Callback', @on_open_stats);

uicontrol('Parent', pnl_defects, 'Style', 'pushbutton', 'String', '🔎 INDAGINE PICCO', ...
    'Units', 'normalized', 'Position', [0.05 0.02 0.9 0.06], ...
    'BackgroundColor', [1 0.9 0.6], 'FontWeight', 'bold', ...
    'Callback', @on_open_single_analysis);

% --- Pannello Storia (Trend + Lista Run) ---
pnl_history = uipanel('Parent', grp_bot, 'Position', [0.19 0.0 0.25 1.0], 'Title', 'Evoluzione Temporale', 'BackgroundColor', 'w');
ax_trend = axes('Parent', pnl_history, 'Units', 'normalized', 'Position', [0.12 0.60 0.85 0.35]); grid on;
h_list_runs = uicontrol('Parent', pnl_history, 'Style', 'listbox', 'String', {}, 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.45], 'Callback', @on_select_run);

% --- Pannello Dettaglio Passaggi (6 Grafici - 3a Riga Dinamica) ---
pnl_signals = uipanel('Parent', grp_bot, 'Position', [0.45 0.0 0.55 1.0], 'Title', 'Dettaglio Passaggi', 'BackgroundColor', 'w');

% Aggiunta Etichetta di Stato (Dinamica)
h_lbl_lat_status = uicontrol('Parent', pnl_signals, 'Style', 'text', ...
    'String', 'In attesa...', 'Units', 'normalized', ...
    'Position', [0.55 0.96 0.43 0.035], ... % In alto a destra nel pannello
    'BackgroundColor', [1 1 0.9], 'ForegroundColor', 'k', ...
    'FontWeight', 'bold', 'FontSize', 9, ...
    'HorizontalAlignment', 'center');

% --- NUOVO: Selettore Segnale (Filt / Raw) ---
uicontrol('Parent', pnl_signals, 'Style', 'text', 'String', 'Visualizzazione:', ...
    'Units', 'normalized', 'Position', [0.02 0.955 0.16 0.035], ...
    'BackgroundColor', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    
uicontrol('Parent', pnl_signals, 'Style', 'popupmenu', ...
    'String', {'Dati Filtrati', 'Dati Grezzi (RAW)'}, 'Units', 'normalized', ...
    'Position', [0.19 0.96 0.20 0.035], 'Callback', @on_sigtype_change);

% Creazione 6 Assi (Standard 2x3)
AxesHandles = gobjects(6,1);
margin_x = 0.06; gap_x = 0.08; 
w_ax = (0.92 - gap_x)/2; 
h_ax = 0.23; 
y_start = 0.68; 
y_gap = 0.30;

% Matrice posizioni standard 2x3
pos_matrix = [
    0.05, y_start;          % 1. Vert SX Front
    0.55, y_start;          % 2. Vert SX Rear
    0.05, y_start-y_gap;    % 3. Vert DX Front
    0.55, y_start-y_gap;    % 4. Vert DX Rear
    0.05, y_start-2*y_gap;  % 5. LAT (Dinamico) Front
    0.55, y_start-2*y_gap   % 6. LAT (Dinamico) Rear
];

for i=1:6
    AxesHandles(i) = axes('Parent', pnl_signals, 'Units', 'normalized', ...
        'Position', [pos_matrix(i,1), pos_matrix(i,2), w_ax, h_ax]); 
    grid on; 
end
%% Data Store

GuiData.ParentFolder = PARENT_FOLDER; GuiData.DBFolder = DB_FOLDER; GuiData.ExcelPath = EXCEL_PATH;
GuiData.TrackList = TrackList; GuiData.GroupList = GroupList; GuiData.GroupMap = GroupMap;
GuiData.Params = DefaultParams; GuiData.DefaultParams = DefaultParams;
GuiData.CFG = CFG;
GuiData.LblLatStatus = h_lbl_lat_status; % Salviamo l'handle
GuiData.Axes = AxesHandles; GuiData.AxContext = ax_context; GuiData.AxCfar = ax_cfar; GuiData.AxTrend = ax_trend;
GuiData.ListDefects = h_list_defects; GuiData.ListRuns = h_list_runs; GuiData.LblStatus = h_status_lbl;GuiData.ListJoints = h_list_joints;
GuiData.Sensors = SensorsOrder(:,1); GuiData.Titles = SensorsOrder(:,2);
GuiData.Mode = 'Filt'; GuiData.CurrDefectIdx = 1; GuiData.CurrRunIdx = 1; GuiData.CurrentTrackName = ''; GuiData.CurrentGroup = GroupList{1};
GuiData.InfraMap = table(); 


%posizione giunti 
GuiData.JointsExcelPath = JOINTS_EXCEL_PATH;

% Controlli Rimasti
GuiData.Edit_N     = h_edit_n;
GuiData.PopupTrack = h_popup_track;
GuiData.BtnDate    = h_btn_date;
GuiData.DateFrom   = '';   % '' = nessun filtro; altrimenti datetime (inizio giorno)
GuiData.DateTo     = '';   % '' = come DateFrom (giorno singolo)
GuiData.AvailDays  = [];   % datetime dei giorni con dati (per il calendario)
GuiData.FullDB     = [];   % DB completo non filtrato
% --- NUOVE VARIABILI VISTA ---
GuiData.PopupView = h_popup_view;
GuiData.ViewMode = 'Both'; % 'Both', 'Front', o 'Rear'

% Salvataggio Handle
guidata(f, GuiData);
on_change_track(h_popup_track, []);

% =========================================================================
% CALLBACKS STANDARD
% =========================================================================
function on_param_change(src, ~)
    h = guidata(src);
    if ~isfield(h, 'Ctrl'), return; end
    h.Params.L_Max = get(h.Ctrl.Sld_LMax, 'Value'); set(h.Ctrl.Lbl_LMax, 'String', sprintf('%.2f m', h.Params.L_Max));
    h.Params.L_Quiet = get(h.Ctrl.Sld_LQuiet, 'Value'); set(h.Ctrl.Lbl_LQuiet, 'String', sprintf('%.2f m', h.Params.L_Quiet));
    h.Params.L_Stress = get(h.Ctrl.Sld_LStress, 'Value'); set(h.Ctrl.Lbl_LStress, 'String', sprintf('%.2f m', h.Params.L_Stress));
    h.Params.Win_Shock = get(h.Ctrl.Sld_WShock, 'Value'); set(h.Ctrl.Lbl_WShock, 'String', sprintf('%.2f m', h.Params.Win_Shock));
    h.Params.Win_Bkg = get(h.Ctrl.Sld_WBkg, 'Value'); set(h.Ctrl.Lbl_WBkg, 'String', sprintf('%.0f m', h.Params.Win_Bkg));
    h.Params.K_Factor = get(h.Ctrl.Sld_K, 'Value'); set(h.Ctrl.Lbl_K, 'String', sprintf('%.1f', h.Params.K_Factor));
    h.Params.Abs_Thresh = get(h.Ctrl.Sld_Abs, 'Value'); set(h.Ctrl.Lbl_Abs, 'String', sprintf('%.1f m/s^2', h.Params.Abs_Thresh));
    guidata(src, h); update_top_plots(h);
end


function on_sigtype_change(src, ~)
    h = guidata(src);
    if get(src, 'Value') == 1
        h.Mode = 'Filt';
    else
        h.Mode = 'Raw';
    end
    guidata(src, h);
    update_signals_only(h); % Aggiorna istantaneamente solo i 6 grafici
end

function on_change_view(src, ~)
    h = guidata(src);
    val = get(src, 'Value');
    opzioni = get(src, 'String');
    scelta = opzioni{val};
    
    if strcmp(scelta, 'Entrambi')
        h.ViewMode = 'Both';
    elseif strcmp(scelta, 'Solo Front')
        h.ViewMode = 'Front';
    elseif strcmp(scelta, 'Solo Rear')
        h.ViewMode = 'Rear';
    end
    
    guidata(src, h);
    update_all_plots(h); % Ridisegna i grafici con il nuovo filtro
end

function on_reset_params(src, ~)
    h = guidata(src); def = h.DefaultParams; h.Params = def;
    if ~isfield(h, 'Ctrl'), return; end
    set(h.Ctrl.Sld_LMax, 'Value', def.L_Max); set(h.Ctrl.Lbl_LMax, 'String', sprintf('%.2f m', def.L_Max));
    set(h.Ctrl.Sld_LQuiet, 'Value', def.L_Quiet); set(h.Ctrl.Lbl_LQuiet, 'String', sprintf('%.2f m', def.L_Quiet));
    set(h.Ctrl.Sld_LStress, 'Value', def.L_Stress); set(h.Ctrl.Lbl_LStress, 'String', sprintf('%.2f m', def.L_Stress));
    set(h.Ctrl.Sld_WShock, 'Value', def.Win_Shock); set(h.Ctrl.Lbl_WShock, 'String', sprintf('%.2f m', def.Win_Shock));
    set(h.Ctrl.Sld_WBkg, 'Value', def.Win_Bkg); set(h.Ctrl.Lbl_WBkg, 'String', sprintf('%.0f m', def.Win_Bkg));
    set(h.Ctrl.Sld_K, 'Value', def.K_Factor); set(h.Ctrl.Lbl_K, 'String', sprintf('%.1f', def.K_Factor));
    set(h.Ctrl.Sld_Abs, 'Value', def.Abs_Thresh); set(h.Ctrl.Lbl_Abs, 'String', sprintf('%.1f m/s^2', def.Abs_Thresh));
    guidata(src, h); update_top_plots(h);
end

function on_change_track(src, ~)
    h = guidata(src); 
    
    % --- FIX ERRORE ---
    % Non possiamo usare 'h_popup_track' direttamente qui.
    % Usiamo l'handle che abbiamo salvato in GuiData.PopupTrack
    h_pop = h.PopupTrack; 
    
    % Recuperiamo l'indice dal popup (indipendentemente da chi ha chiamato la funzione: popup o edit box)
    idx = get(h_pop, 'Value');
    
    trackName = h.TrackList{idx}; 
    h.CurrentTrackName = trackName;
    
    set(h.LblStatus, 'String', 'Caricamento...', 'ForegroundColor', 'b'); drawnow;
    
    % 2. Caricamento Mappa Infrastruttura
    if contains(lower(h.ParentFolder), 'pari'), t_type = 'pari'; else, t_type = 'dispari'; end
    h.InfraMap = load_infrastructure_map(h.ExcelPath, t_type);


    % NUOVO: Caricamento Mappa Giunti
    h.JointsMap = load_joints_map(h.JointsExcelPath, t_type);

    % NUOVO: popola la lista giunti della SOLA tratta selezionata
    if ~isempty(h.JointsMap) && height(h.JointsMap) > 0
        % Filtra i giunti la cui colonna Stations corrisponde alla tratta corrente
        mask_tr = strcmp(strtrim(string(h.JointsMap.Stations)), strtrim(string(trackName)));
        Jt = h.JointsMap(mask_tr, :);
        
        if height(Jt) > 0
            [~, ord] = sort(Jt.Position);
            Jt = Jt(ord, :);
            joint_strs = cell(height(Jt), 1);
            for k = 1:height(Jt)
                joint_strs{k} = sprintf('%s  @ %d m', Jt.Joint(k), Jt.Position(k));
            end
            set(h.ListJoints, 'String', joint_strs, 'Value', 1);
        else
            set(h.ListJoints, 'String', {'(nessun giunto per questa tratta)'}, 'Value', 1);
        end
    else
        set(h.ListJoints, 'String', {'(nessun giunto)'}, 'Value', 1);
    end

    % 3. Caricamento Database
    dbFile = fullfile(h.DBFolder, ['Database_damage_' trackName '.mat']);
    
    if exist(dbFile, 'file')
        loaded = load(dbFile);
       if isfield(loaded, 'MASTER_DB')
            h.FullDB = loaded.MASTER_DB;

            % Popola popup con i giorni unici da tutta la storia
            all_days = [];
            for kk = 1:length(h.FullDB)
                if isfield(h.FullDB(kk), 'History') && ~isempty(h.FullDB(kk).History)
                    all_days = [all_days, dateshift([h.FullDB(kk).History.Date], 'start', 'day')]; %#ok<AGROW>
                end
            end
            h.AvailDays = sort(unique(all_days(:)));   % datetime, crescente
            h.DateFrom = ''; h.DateTo = '';            % reset filtro al cambio tratta
            set(h.BtnDate, 'String', '📅  Tutti i Giorni');

            guidata(src, h);
            refresh_defect_list(src, h);
        else
            set(h.LblStatus, 'String', 'DB Corrotto', 'ForegroundColor', 'r');
        end
    else
        set(h.LblStatus, 'String', 'DB non trovato', 'ForegroundColor', 'r'); 
        set(h.ListDefects, 'String', {}, 'Value', 1); 
        cla_all(h); 
        h.DB = []; 
        guidata(src, h);
    end
end


function on_change_group(src, ~)
    h = guidata(src); 
    idx = get(src, 'Value'); 
    
    % Recupera il nome del gruppo selezionato
    selected_group = h.GroupList{idx};
    h.CurrentGroup = selected_group;
    
    % DEBUG: Conferma selezione
    fprintf('\n--- CAMBIO GRUPPO: %s ---\n', selected_group);
    
    % Salva e aggiorna
    guidata(src, h); 
    update_top_plots(h);
end
% function on_change_group(src, ~)
%     h = guidata(src); idx = get(src, 'Value'); 
%     h.CurrentGroup = h.GroupList{idx}; % Aggiorna il gruppo corrente (SX o DX)
%     guidata(src, h); update_top_plots(h);
% end

% =========================================================================
% CALENDARIO (selezione giorno singolo o intervallo)
% =========================================================================
function pos = center_on_screen(w, hgt)
    ss = get(0, 'ScreenSize');
    pos = [ (ss(3)-w)/2, (ss(4)-hgt)/2, w, hgt ];
end

function open_calendar_dialog(main_fig)
    h = guidata(main_fig);
    if ~isfield(h, 'AvailDays') || isempty(h.AvailDays)
        msgbox('Nessun giorno disponibile (carica prima una tratta).', 'Calendario');
        return;
    end
    st.main_fig = main_fig;
    st.avail = sort(h.AvailDays(:));
    if isfield(h, 'DateFrom') && ~isempty(h.DateFrom)
        st.sel_from = h.DateFrom;
        if isfield(h, 'DateTo') && ~isempty(h.DateTo), st.sel_to = h.DateTo; else, st.sel_to = h.DateFrom; end
        st.view_month = dateshift(st.sel_from, 'start', 'month');
    else
        st.sel_from = []; st.sel_to = [];
        st.view_month = dateshift(st.avail(end), 'start', 'month');
    end
    st.stage = 0;

    dlg = figure('Name', 'Calendario', 'NumberTitle', 'off', 'MenuBar', 'none', ...
        'ToolBar', 'none', 'Color', 'w', 'Units', 'pixels', ...
        'Position', center_on_screen(360, 430), 'WindowStyle', 'modal', 'Resize', 'off');
    st.dlg = dlg;
    guidata(dlg, st);
    render_calendar(dlg);
end

function render_calendar(dlg)
    st = guidata(dlg);
    delete(findobj(dlg, 'Type', 'uicontrol'));

    mesi   = {'gennaio','febbraio','marzo','aprile','maggio','giugno', ...
              'luglio','agosto','settembre','ottobre','novembre','dicembre'};
    giorni = {'Lu','Ma','Me','Gi','Ve','Sa','Do'};
    blu    = [0 0.45 0.85];
    rng    = [0.86 0.90 0.96];
    grigio = [0.70 0.70 0.70];

    uicontrol('Parent', dlg, 'Style', 'text', 'String', 'Calendario', ...
        'Units', 'pixels', 'Position', [0 398 360 24], ...
        'BackgroundColor', 'w', 'ForegroundColor', blu, 'FontSize', 13, 'FontWeight', 'bold');

    uicontrol('Parent', dlg, 'Style', 'pushbutton', 'String', '<', ...
        'Units', 'pixels', 'Position', [18 360 36 28], 'FontSize', 12, ...
        'Callback', @(s,e) calendar_nav(dlg, -1));
    uicontrol('Parent', dlg, 'Style', 'pushbutton', 'String', '>', ...
        'Units', 'pixels', 'Position', [306 360 36 28], 'FontSize', 12, ...
        'Callback', @(s,e) calendar_nav(dlg, +1));
    mlabel = sprintf('%s %d', mesi{month(st.view_month)}, year(st.view_month));
    uicontrol('Parent', dlg, 'Style', 'text', 'String', mlabel, ...
        'Units', 'pixels', 'Position', [60 358 240 26], ...
        'BackgroundColor', 'w', 'FontSize', 12, 'FontWeight', 'bold');

    cellW = 44; gap = 2; x0 = 18;
    for c = 1:7
        x = x0 + (c-1)*(cellW+gap);
        uicontrol('Parent', dlg, 'Style', 'text', 'String', giorni{c}, ...
            'Units', 'pixels', 'Position', [x 332 cellW 18], ...
            'BackgroundColor', 'w', 'ForegroundColor', grigio, 'FontWeight', 'bold');
    end

    first = dateshift(st.view_month, 'start', 'month');
    col0  = mod(weekday(first)-2, 7);            % 0 = lunedi'
    ndays = eomday(year(first), month(first));

    selA = st.sel_from; selB = st.sel_to;
    if ~isempty(selA) && isempty(selB), selB = selA; end
    if ~isempty(selA) && ~isempty(selB) && selB < selA, t=selA; selA=selB; selB=t; end
    oggi = dateshift(datetime('now'), 'start', 'day');

    for n = 1:ndays
        d = first + caldays(n-1);
        pos_idx = col0 + (n-1);
        r = floor(pos_idx/7); c = mod(pos_idx, 7);
        x = x0 + c*(cellW+gap);
        y = 292 - r*38;

        avail_day = any(st.avail == d);
        bg = 'w'; fg = 'k'; en = 'on'; fw = 'normal';
        if ~avail_day, fg = grigio; en = 'off'; end
        if ~isempty(selA)
            if isequal(d, selA) || isequal(d, selB)
                bg = blu; fg = 'w'; fw = 'bold';
            elseif d > selA && d < selB
                bg = rng;
            end
        end
        if avail_day && (isempty(selA) || (~isequal(d,selA) && ~isequal(d,selB))) && isequal(d, oggi)
            fg = blu; fw = 'bold';
        end

        uicontrol('Parent', dlg, 'Style', 'pushbutton', 'String', num2str(n), ...
            'Units', 'pixels', 'Position', [x y cellW 34], ...
            'BackgroundColor', bg, 'ForegroundColor', fg, 'FontWeight', fw, ...
            'Enable', en, 'Callback', @(s,e) calendar_pick(dlg, d));
    end

    uicontrol('Parent', dlg, 'Style', 'pushbutton', 'String', 'Tutti i Giorni', ...
        'Units', 'pixels', 'Position', [18 18 120 32], ...
        'Callback', @(s,e) calendar_clear(dlg));
    uicontrol('Parent', dlg, 'Style', 'pushbutton', 'String', 'Annulla', ...
        'Units', 'pixels', 'Position', [150 18 90 32], ...
        'Callback', @(s,e) close(dlg));
    uicontrol('Parent', dlg, 'Style', 'pushbutton', 'String', 'Applica', ...
        'Units', 'pixels', 'Position', [250 18 92 32], ...
        'BackgroundColor', blu, 'ForegroundColor', 'w', 'FontWeight', 'bold', ...
        'Callback', @(s,e) calendar_apply(dlg));
end

function calendar_nav(dlg, delta)
    st = guidata(dlg);
    st.view_month = dateshift(st.view_month + calmonths(delta), 'start', 'month');
    guidata(dlg, st);
    render_calendar(dlg);
end

function calendar_pick(dlg, d)
    st = guidata(dlg);
    if st.stage == 0
        st.sel_from = d; st.sel_to = []; st.stage = 1;
    else
        st.sel_to = d;
        if ~isempty(st.sel_from) && st.sel_to < st.sel_from
            t = st.sel_from; st.sel_from = st.sel_to; st.sel_to = t;
        end
        st.stage = 0;
    end
    guidata(dlg, st);
    render_calendar(dlg);
end

function calendar_clear(dlg)
    st = guidata(dlg);
    st.sel_from = []; st.sel_to = []; st.stage = 0;
    guidata(dlg, st);
    calendar_apply(dlg);
end

function calendar_apply(dlg)
    st = guidata(dlg);
    mf = st.main_fig; h = guidata(mf);
    if isempty(st.sel_from)
        h.DateFrom = ''; h.DateTo = '';
        set(h.BtnDate, 'String', '📅  Tutti i Giorni');
    else
        d1 = st.sel_from; d2 = st.sel_to; if isempty(d2), d2 = d1; end
        if d2 < d1, t=d1; d1=d2; d2=t; end
        h.DateFrom = d1; h.DateTo = d2;
        if isequal(d1, d2)
            set(h.BtnDate, 'String', ['📅  ' datestr(d1, 'dd/mm/yyyy')]);
        else
            set(h.BtnDate, 'String', ['📅  ' datestr(d1, 'dd/mm') ' -> ' datestr(d2, 'dd/mm/yyyy')]);
        end
    end
    guidata(mf, h);
    if isvalid(st.dlg), close(st.dlg); end
    refresh_defect_list(mf, h);
end


% =========================================================================
% FILTRO-GIORNO applicato ai report: ritaglia la History a un intervallo
% =========================================================================
function Dsub = filter_defect_by_dates(Defect, d1, d2)
    Dsub = Defect;
    if isempty(d1), return; end
    if isempty(d2), d2 = d1; end
    if d2 < d1, t=d1; d1=d2; d2=t; end
    H = Defect.History;
    if isempty(H), return; end
    dk = dateshift([H.Date], 'start', 'day');
    Dsub.History = H(dk >= d1 & dk <= d2);
    % Ricalcola gli aggregati sulla sola finestra temporale
    Hs = Dsub.History;
    if isempty(Hs)
        if isfield(Dsub,'Num_Occurrences'), Dsub.Num_Occurrences = 0; end
        if isfield(Dsub,'Num_Total_Runs'),  Dsub.Num_Total_Runs  = 0; end
        if isfield(Dsub,'Max_Severity'),     Dsub.Max_Severity     = 0; end
        return;
    end
    amps = [Hs.Amp];
    if isfield(Dsub,'Max_Severity'),    Dsub.Max_Severity    = max(amps); end
    if isfield(Dsub,'Num_Total_Runs'),  Dsub.Num_Total_Runs  = numel(Hs); end
    if isfield(Dsub,'Num_Occurrences')
        if isfield(Hs,'Detected'), Dsub.Num_Occurrences = sum([Hs.Detected]);
        else,                      Dsub.Num_Occurrences = numel(Hs); end
    end
end

function DBsub = filter_db_by_dates(DB, d1, d2)
    if isempty(d1) || isempty(DB), DBsub = DB; return; end
    DBsub = DB;
    keepDefect = false(1, numel(DB));
    for i = 1:numel(DB)
        DBsub(i) = filter_defect_by_dates(DB(i), d1, d2);
        keepDefect(i) = ~isempty(DBsub(i).History);
    end
    DBsub = DBsub(keepDefect);
end
function on_change_n(src, ~)
    h = guidata(src);
    if ~isfield(h, 'FullDB') || isempty(h.FullDB), return; end
    refresh_defect_list(src, h);
end


function refresh_defect_list(src, h)
    % Filtro 1: numero occorrenze
    n_min = str2double(get(h.Edit_N, 'String'));
    if isnan(n_min), n_min = 0; end
    mask_n  = [h.FullDB.Num_Occurrences] >= n_min;
    db_filt = h.FullDB(mask_n);

    % Filtro 2: intervallo di giorni (o giorno singolo se DateTo == DateFrom)
    if ~isempty(h.DateFrom)
        d1 = h.DateFrom; d2 = h.DateTo; if isempty(d2), d2 = d1; end
        if d2 < d1, tmp=d1; d1=d2; d2=tmp; end
        date_mask = false(1, length(db_filt));
        for ii = 1:length(db_filt)
            if isfield(db_filt(ii), 'History') && ~isempty(db_filt(ii).History)
                days = dateshift([db_filt(ii).History.Date], 'start', 'day');
                if any(days >= d1 & days <= d2)
                    date_mask(ii) = true;
                end
            end
        end
        db_filt = db_filt(date_mask);
    end

    h.DB = db_filt;

    set(h.LblStatus, 'String', sprintf('OK: %s (Visualizzati: %d/%d)', ...
        h.CurrentTrackName, length(h.DB), length(h.FullDB)), ...
        'ForegroundColor', [0 0.6 0]);

    pk_list = cell(length(h.DB), 1);
    for i = 1:length(h.DB)
        d = h.DB(i);
        infra_tag = "";
        if isfield(d, 'Infrastructure') && strlength(d.Infrastructure) > 0 && d.Infrastructure ~= "Linea"
            tag_str = char(d.Infrastructure);
            if length(tag_str) > 16, tag_str = [tag_str(1:16) '..']; end
            infra_tag = [' [' tag_str ']'];
        end
        n_tot = d.Num_Occurrences;
        if isfield(d, 'Num_Total_Runs'), n_tot = d.Num_Total_Runs; end
        pk_list{i} = sprintf('%s%s (%d/%d) %.1f m/s^2', d.ID_PK, infra_tag, d.Num_Occurrences, n_tot, d.Max_Severity);
    end

    set(h.ListDefects, 'String', pk_list);

    if isempty(pk_list)
        set(h.ListDefects, 'Value', 1);
        h.CurrDefectIdx = [];
    else
        val = get(h.ListDefects, 'Value');
        if isempty(val) || any(val > length(pk_list)) || any(val == 0)
            set(h.ListDefects, 'Value', 1);
            h.CurrDefectIdx = 1;
        else
            h.CurrDefectIdx = val(1);
            set(h.ListDefects, 'Value', val(1));
        end
    end

    h.CurrRunIdx = 1;
    guidata(src, h);

    if ~isempty(h.DB) && ~isempty(pk_list)
        on_select_defect(h.ListDefects, []);
    else
        cla_all(h);
        title(h.AxTrend, 'Nessun difetto trovato con questo filtro');
    end
end


function on_select_defect(src, ~)
    h = guidata(src); idx = get(src, 'Value'); if isempty(h.DB)||isempty(idx), return; end
    h.CurrDefectIdx = idx; Defect = h.DB(idx); History = Defect.History;
    dates = [History.Date]; amps = [History.Amp]; [dates, sort_order] = sort(dates); amps = amps(sort_order);

    cla(h.AxTrend); hold(h.AxTrend, 'off');
    detected = true(size(amps));
    if isfield(History, 'Detected'), detected = [History(sort_order).Detected]; end
    plot(h.AxTrend, dates, amps, '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 1);
    hold(h.AxTrend, 'on');
    plot(h.AxTrend, dates(detected), amps(detected), 'o', 'Color', 'b', 'MarkerFaceColor', 'b', 'MarkerSize', 6);
    if any(~detected)
        plot(h.AxTrend, dates(~detected), amps(~detected), 'x', 'Color', [0.8 0 0], 'MarkerSize', 7, 'LineWidth', 1.5);
    end
    datetick(h.AxTrend, 'x', 'dd/mm', 'keepticks'); xtickangle(h.AxTrend, 45);
    
    title_str = ['Trend ' Defect.ID_PK];
    if isfield(Defect, 'Infrastructure'), title_str = [title_str ' - ' char(Defect.Infrastructure)]; end
    title(h.AxTrend, title_str, 'Interpreter', 'none', 'FontSize', 8); grid(h.AxTrend, 'on');
    
    % Se il filtro-giorno e' attivo, mostra nella lista passaggi SOLO le run di quel giorno
    day_keys = dateshift(dates, 'start', 'day');   % 'dates' e' datetime, gia' ordinato
    if isfield(h,'DateFrom') && ~isempty(h.DateFrom)
        d1 = h.DateFrom; d2 = h.DateTo; if isempty(d2), d2 = d1; end
        if d2 < d1, tmp=d1; d1=d2; d2=tmp; end
        keep = (day_keys >= d1 & day_keys <= d2);
    else
        keep = true(size(day_keys));
    end

    run_strs = {}; run_map = [];
    for k=1:length(History)
        if ~keep(k), continue; end
        orig_idx = sort_order(k);
        tag = '';
        if isfield(History, 'Detected') && ~History(orig_idx).Detected, tag = ' [NO TRIG]'; end
        run_strs{end+1,1} = sprintf('%s - %.1f m/s^2%s', datestr(History(orig_idx).Date, 'dd/mm HH:MM'), History(orig_idx).Amp, tag); %#ok<AGROW>
        run_map(end+1)    = orig_idx; %#ok<AGROW>
    end

    if isempty(run_map)
        set(h.ListRuns, 'String', {'(nessun passaggio in questo giorno)'}, 'Value', 1, 'UserData', []);
        guidata(src, h); return;
    end

    set(h.ListRuns, 'String', run_strs, 'Value', length(run_strs), 'UserData', run_map);
    h.CurrRunIdx = run_map(end); guidata(src, h); update_all_plots(h);
end

function on_select_run(src, ~)
    h = guidata(src); list_idx = get(src, 'Value'); map = get(src, 'UserData');
    if isempty(list_idx), return; end
    h.CurrRunIdx = map(list_idx); guidata(src, h); update_all_plots(h);
end

function on_type_change(~, event), h = guidata(event.NewValue); h.Mode = upper(event.NewValue.String); if strcmpi(h.Mode, 'FILTERED'), h.Mode='Filt'; else, h.Mode='Raw'; end, guidata(event.NewValue, h); update_all_plots(h); end


function update_all_plots(h), update_signals_only(h); update_top_plots(h); end

% =========================================================================
% CALLBACK: GENERAZIONE REPORT STATISTICO GLOBALE
% =========================================================================
function on_open_stats(src, ~)
    h = guidata(src);
    if isempty(h.DB)
        msgbox('Nessun database caricato.', 'Errore', 'error'); 
        return; 
    end
    
    if length(h.DB) > 1000
        choice = questdlg(sprintf('Il database contiene %d difetti. Procedere?', length(h.DB)), ...
            'Elaborazione Massiva', 'Sì', 'No', 'Sì');
        if ~strcmp(choice, 'Sì'), return; end
    end
    
    % Genera report usando il GRUPPO CORRENTE (Left o Right)
    DB_win = h.DB;
    if isfield(h,'DateFrom') && ~isempty(h.DateFrom)
        DB_win = filter_db_by_dates(h.DB, h.DateFrom, h.DateTo);
        if isempty(DB_win)
            msgbox('Nessun difetto con passaggi nell''intervallo selezionato.', 'Report'); return;
        end
    end
    generate_global_report(DB_win, h.CurrentGroup, h.GroupMap, h.CFG, h.CurrentTrackName, h);
end

%% fine pre cambiamenti

% =========================================================================
% FUNZIONE CORE: REPORT GLOBALE COMPLETO (TUTTI I GRUPPI SENSORI)
% =========================================================================
function generate_global_report(DB, ~, map, C, track_name,h_main)
    % Definiamo i 4 gruppi da estrarre massivamente
    Groups = {'Verticale SX', 'Verticale DX', 'Laterale DX', 'Laterale SX'};
    


    % Inizializziamo una struttura dati per raccogliere tutto senza fare confusione
    DataStore = struct();
    for g = 1:4
        sensors = map(Groups{g});
        DataStore(g).Name = Groups{g};
        DataStore(g).sF   = sensors{1};
        DataStore(g).sR   = sensors{2};
        
        % Inizializzazione sicura (evita l'errore struct 0x0 di MATLAB)
        DataStore(g).Filt.PkF = [];  DataStore(g).Filt.PkR = [];
        DataStore(g).Filt.MovF = []; DataStore(g).Filt.MovR = [];
        DataStore(g).Filt.GlbF = []; DataStore(g).Filt.GlbR = [];
        DataStore(g).Filt.Meta = {};
        DataStore(g).Filt.DefectID = [];
        DataStore(g).Raw.PkF = [];  DataStore(g).Raw.PkR = [];
        DataStore(g).Raw.MovF = []; DataStore(g).Raw.MovR = [];
        DataStore(g).Raw.GlbF = []; DataStore(g).Raw.GlbR = [];
        DataStore(g).Raw.Meta = {};
        DataStore(g).Raw.DefectID = [];
    end

    % Carica modello AE per la tratta (una volta sola)
    AE_Model = load_ae_model_for_track(track_name);
    if AE_Model.loaded
        fprintf('[Report Globale] AE attivo per tratta "%s"\n', track_name);
    else
        fprintf('[Report Globale] AE non disponibile - Bonus IA sarà 0 per tutti\n');
    end
    
    wb = waitbar(0, 'Estrazione dati per TUTTI i gruppi di sensori...');
    n_db = length(DB);
    for i = 1:n_db
        if mod(i, 20) == 0, waitbar(i/n_db, wb); end
        Defect = DB(i);
        
        for j = 1:length(Defect.History)
            RunData = Defect.History(j);
            if isfield(RunData, 'Detected') && ~RunData.Detected, continue; end
            meta_str = sprintf('PK: %s Passaggio: %s', Defect.ID_PK, datestr(RunData.Date, 'dd/mm/yy'));
            
            % Calcolo della finestra spaziale per l'RMS a 0.5m
            dx = 0.01; % Default
            win_05m = max(1, round(0.5 / dx));
            
            % Ciclo su tutti i 4 gruppi per questo singolo passaggio
            for g = 1:4
                sF = DataStore(g).sF;
                sR = DataStore(g).sR;
                
                % --- ESTRAZIONE DATI FILTRATI ---
                if isfield(RunData.Data, 'Filt') && isfield(RunData.Data.Filt, sF) && isfield(RunData.Data.Filt, sR)
                    sigF = double(RunData.Data.Filt.(sF)); 
                    sigR = double(RunData.Data.Filt.(sR));
                    
                    if ~isempty(sigF) && ~isempty(sigR)
                        DataStore(g).Filt.GlbF(end+1, 1) = rms(sigF); 
                        DataStore(g).Filt.GlbR(end+1, 1) = rms(sigR);
                        DataStore(g).Filt.PkF(end+1, 1)  = max(abs(sigF)); 
                        DataStore(g).Filt.PkR(end+1, 1)  = max(abs(sigR));
                        DataStore(g).Filt.MovF(end+1, 1) = max(sqrt(movmean(sigF.^2, win_05m))); 
                        DataStore(g).Filt.MovR(end+1, 1) = max(sqrt(movmean(sigR.^2, win_05m)));
                        DataStore(g).Filt.Meta{end+1}    = meta_str;
                        DataStore(g).Filt.DefectID(end+1, 1) = i; % Indice univoco del difetto
                    end
                end
                
                % --- ESTRAZIONE DATI RAW ---
                if isfield(RunData.Data, 'Raw') && isfield(RunData.Data.Raw, sF) && isfield(RunData.Data.Raw, sR)
                    sigF_r = double(RunData.Data.Raw.(sF)); 
                    sigR_r = double(RunData.Data.Raw.(sR));
                    
                    if ~isempty(sigF_r) && ~isempty(sigR_r)
                        DataStore(g).Raw.GlbF(end+1, 1) = rms(sigF_r); 
                        DataStore(g).Raw.GlbR(end+1, 1) = rms(sigR_r);
                        DataStore(g).Raw.PkF(end+1, 1)  = max(abs(sigF_r)); 
                        DataStore(g).Raw.PkR(end+1, 1)  = max(abs(sigR_r));
                        DataStore(g).Raw.MovF(end+1, 1) = max(sqrt(movmean(sigF_r.^2, win_05m))); 
                        DataStore(g).Raw.MovR(end+1, 1) = max(sqrt(movmean(sigR_r.^2, win_05m)));
                        DataStore(g).Raw.Meta{end+1}    = meta_str;
                        DataStore(g).Raw.DefectID(end+1, 1) = i; % Indice univoco del difetto
                    end
                end
            end
        end
    end
    % =========================================================
    % NUOVO: CALCOLO IPI GLOBALE (TREND + LATERALE)
    % =========================================================
    waitbar(1, wb, 'Calcolo Indice Rischio Degrado (IPI)...');
    
    % Soglia minima passaggi storici (parametrica via CFG)
    min_runs_req = C.IPI_MIN_RUNS;
    
    IpiData = struct('ID', {}, 'IPI', {}, 'SAbsolute', {}, 'STrend', {}, 'BonusLat', {}, 'IncPerc', {}, ...
                 'RecentRMS', {}, 'NRuns', {}, 'BonusPCA', {}, 'PcaIncPerc', {}, ...
                 'PcaExcursions', {}, 'PcaBonusTrend', {}, 'PcaBonusExcur', {}, ...
                 'BonusIA', {}, 'IAAccRecent', {}, 'MaxVert', {}, 'MaxLat', {}); % AGGIUNTO SAbsolute
    for i = 1:n_db
        Defect = DB(i);
        n_runs = length(Defect.History);
        ipi_final = -1; S_absolute = 0; S_trend = 0; Bonus_lat = 0; inc_perc = 0; rms_recent = 0;
        max_v = 0; max_l = 0; 
        
        if n_runs >= min_runs_req
            temp_Sev = zeros(n_runs, 1);
            temp_Rat = zeros(n_runs, 1);
            temp_Dat = zeros(n_runs, 1);
            temp_Lat = zeros(n_runs, 1); 
            
            for k = 1:n_runs
                run = Defect.History(k);
                temp_Dat(k) = floor(datenum(run.Date)); 
                if isfield(run.Data, 'Filt')
                    F = run.Data.Filt;
                    win_samples = max(3, round(0.5 / C.SPATIAL_RES));   
                    A_VERT_MAX = max([get_max_rms(F,'left_sensor_front',win_samples),  get_max_rms(F,'left_sensor_rear',win_samples), ...
                        get_max_rms(F,'right_sensor_front',win_samples), get_max_rms(F,'right_sensor_rear',win_samples)]);
                    A_LAT_MAX  = max([get_max_rms(F,'right_sensor_front_lat',win_samples), get_max_rms(F,'right_sensor_rear_lat',win_samples), ...
                        get_max_rms(F,'left_sensor_front_lat', win_samples), get_max_rms(F,'left_sensor_rear_lat', win_samples)]);
                    temp_Sev(k) = A_VERT_MAX;
                    temp_Lat(k) = A_LAT_MAX; 
                    if A_VERT_MAX > 1e-6
                        temp_Rat(k) = A_LAT_MAX / A_VERT_MAX;
                    end
                end
            end
            
            max_v = max(temp_Sev);
            max_l = max(temp_Lat);
            
            unique_days = unique(temp_Dat);
            n_days = length(unique_days);
            history_span = unique_days(end) - unique_days(1);
            
            if history_span >= C.IPI_MIN_HISTORY_DAYS && n_days >= C.IPI_MIN_DAYS
                Severity_Daily = zeros(n_days, 1);
                Ratio_LV_Daily = zeros(n_days, 1);
                
                for d = 1:n_days
                    mask = (temp_Dat == unique_days(d));
                    Severity_Daily(d) = mean(temp_Sev(mask), 'omitnan');
                    Ratio_LV_Daily(d) = mean(temp_Rat(mask), 'omitnan');
                end
                
                cutoff_day  = unique_days(end) - C.IPI_RECENT_DAYS;
                mask_recent = unique_days >  cutoff_day;
                mask_base   = unique_days <= cutoff_day;
                
                if any(mask_recent) && any(mask_base)
                    rms_base   = mean(Severity_Daily(mask_base),   'omitnan');
                    rms_recent = mean(Severity_Daily(mask_recent), 'omitnan');
                    
                    % 1. VOTO BASE: TREND (Max 50 Punti)
                    if rms_base > 0
                        inc_perc = ((rms_recent - rms_base) / rms_base) * 100;
                        S_trend = min(50, max(0, inc_perc * (50 / C.IPI_TREND_SENS)));
                    end
                    
                    % 2. VOTO BASE: SEVERITÀ ASSOLUTA (Max 50 Punti)
                    if rms_recent < C.IPI_SEV_THR_LOW
                        S_absolute = 0;
                    elseif rms_recent > C.IPI_SEV_THR_HIGH
                        S_absolute = 50;
                    else
                        S_absolute = 50 * (rms_recent - C.IPI_SEV_THR_LOW) / (C.IPI_SEV_THR_HIGH - C.IPI_SEV_THR_LOW);
                    end
                    
                    % 3. Aggravante Laterale
                    recent_ratio_lv = mean(Ratio_LV_Daily(mask_recent), 'omitnan');
                    Bonus_lat = min(C.IPI_LAT_BONUS, max(0, (recent_ratio_lv / C.IPI_LAT_THRESH) * C.IPI_LAT_BONUS));
                end
                
                % 4. Bonus PCA
                [Bonus_pca, pca_info] = compute_pca_bonus_for_defect(Defect, C);
                
                % 5. Bonus IA
                [Bonus_ia, ia_info] = compute_ae_bonus_for_defect(Defect, AE_Model, C);
                
                % 6. IPI Finale Bilanciato
                ipi_raw = S_absolute + S_trend + Bonus_lat + Bonus_pca + Bonus_ia;
                ipi_final = round(min(100, max(0, ipi_raw)));
            end
        end
        
        IpiData(i).ID         = Defect.ID_PK;
        IpiData(i).IPI        = ipi_final;
        IpiData(i).SAbsolute  = S_absolute; % SALVATAGGIO
        IpiData(i).STrend     = S_trend;
        IpiData(i).BonusLat   = Bonus_lat;
        IpiData(i).IncPerc    = inc_perc;
        IpiData(i).RecentRMS  = rms_recent;
        IpiData(i).NRuns      = n_runs;
        
        if ~exist('Bonus_pca', 'var') || ~exist('pca_info', 'var')
            Bonus_pca = 0; pca_info  = struct('pca_inc_perc',0, 'n_excursions',0, 'bonus_trend',0, 'bonus_excursion',0);
        end
        if ~exist('Bonus_ia', 'var') || ~exist('ia_info', 'var')
            Bonus_ia = 0; ia_info  = struct('valid_runs',0, 'acc_recent',NaN, 'n_days_ae',0);
        end
        
        IpiData(i).BonusPCA      = Bonus_pca;
        IpiData(i).PcaIncPerc    = pca_info.pca_inc_perc;
        IpiData(i).PcaExcursions = pca_info.n_excursions;
        IpiData(i).PcaBonusTrend = pca_info.bonus_trend;
        IpiData(i).PcaBonusExcur = pca_info.bonus_excursion;
        IpiData(i).BonusIA       = Bonus_ia;
        IpiData(i).IAAccRecent   = ia_info.acc_recent;
        IpiData(i).MaxVert       = max_v; 
        IpiData(i).MaxLat        = max_l; 
    end
    close(wb);
    % Filtra quelli validi (almeno 5 run) e ordina
    valid_idx = [IpiData.IPI] >= 0;
    ValidIpiData = IpiData(valid_idx);
    [~, sort_idx] = sort([ValidIpiData.IPI], 'descend');
    SortedIpi = ValidIpiData(sort_idx);

    
   
    % =========================================================
    % COSTRUZIONE INTERFACCIA A TAB NIDIFICATI
    % =========================================================
    f_global = figure('Name', 'Report Statistico Globale Completo', 'Color', 'w', 'WindowState', 'maximized');
    
    % 1. Crea il pulsante in alto a destra
    uicontrol('Parent', f_global, 'Style', 'pushbutton', ...
        'String', '📄 ESPORTA REPORT TRATTA (PDF)', ...
        'Units', 'normalized', 'Position', [0.80 0.94 0.19 0.05], ...
        'BackgroundColor', [0.8 1 0.8], 'FontWeight', 'bold', ...
        'Callback', @(~,~) export_route_report_callback(DataStore, SortedIpi, DB, C, track_name, h_main));

    % 2. Crea il TabGroup abbassandolo (altezza 0.93 anziché 1) per non coprire il pulsante
    tg_main = uitabgroup(f_global, 'Units', 'normalized', 'Position', [0 0 1 0.93]);
    % ---------------------------------------------------------
    % MACRO-TAB 1: DATI FILTRATI
    % ---------------------------------------------------------
    tab_filt = uitab(tg_main, 'Title', 'Dati FILTRATI');
    tg_filt_groups = uitabgroup(tab_filt); % Sotto-Tab per i Gruppi Sensori
    
    for g = 1:4
        ds = DataStore(g);
        t_grp = uitab(tg_filt_groups, 'Title', sprintf('%s (%d Ev.)', ds.Name, length(ds.Filt.PkF)));
        
        if ~isempty(ds.Filt.PkF)
            tg_metrics = uitabgroup(t_grp); % Mini-Tab per le Metriche
            % AGGIUNTO ds.Filt.DefectID ALLA FINE DI OGNI RIGA
            draw_4_panel_stats(uitab(tg_metrics, 'Title', '1. Picco Assoluto'), ds.Filt.PkF, ds.Filt.PkR, ds.Name, ds.Filt.Meta, ds.Filt.DefectID);
            draw_4_panel_stats(uitab(tg_metrics, 'Title', '2. Max RMS (0.5m)'), ds.Filt.MovF, ds.Filt.MovR, ds.Name, ds.Filt.Meta, ds.Filt.DefectID);
            draw_4_panel_stats(uitab(tg_metrics, 'Title', '3. RMS Globale (6m)'), ds.Filt.GlbF, ds.Filt.GlbR, ds.Name, ds.Filt.Meta, ds.Filt.DefectID);
        else
            ax_err = axes('Parent', t_grp, 'Visible', 'off');
            text(ax_err, 0.5, 0.5, 'Nessun dato valido registrato per questo gruppo.', 'HorizontalAlignment', 'center', 'FontSize', 12);
        end
    end
    
    % ---------------------------------------------------------
    % MACRO-TAB 2: DATI GREZZI (RAW)
    % ---------------------------------------------------------
    tab_raw = uitab(tg_main, 'Title', 'Dati GREZZI/RAW');
    tg_raw_groups = uitabgroup(tab_raw); % Sotto-Tab per i Gruppi Sensori
    
    for g = 1:4
        ds = DataStore(g);
        t_grp = uitab(tg_raw_groups, 'Title', sprintf('%s (%d Ev.)', ds.Name, length(ds.Raw.PkF)));
        
        if ~isempty(ds.Raw.PkF)
            tg_metrics = uitabgroup(t_grp); % Mini-Tab per le Metriche
            % AGGIUNTO ds.Raw.DefectID ALLA FINE DI OGNI RIGA
            draw_4_panel_stats(uitab(tg_metrics, 'Title', '1. Picco Assoluto'), ds.Raw.PkF, ds.Raw.PkR, ds.Name, ds.Raw.Meta, ds.Raw.DefectID);
            draw_4_panel_stats(uitab(tg_metrics, 'Title', '2. Max RMS (0.5m)'), ds.Raw.MovF, ds.Raw.MovR, ds.Name, ds.Raw.Meta, ds.Raw.DefectID);
            draw_4_panel_stats(uitab(tg_metrics, 'Title', '3. RMS Globale (6m)'), ds.Raw.GlbF, ds.Raw.GlbR, ds.Name, ds.Raw.Meta, ds.Raw.DefectID);
        else
            ax_err = axes('Parent', t_grp, 'Visible', 'off');
            text(ax_err, 0.5, 0.5, 'Nessun dato RAW salvato per questo gruppo.', 'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', 'r');
        end
    end
    
    % Datatip Globale
    dcm_global = datacursormode(f_global); 
    set(dcm_global, 'Enable', 'on', 'UpdateFcn', @custom_datatip_robust);

    % =========================================================
    % NUOVO MACRO-TAB 3: CLASSIFICA IPI (RISCHIO DEGRADO)
    % =========================================================
    tab_ipi = uitab(tg_main, 'Title', '🏆 Classifica Degrado (IPI)');
    
    uicontrol('Parent', tab_ipi, 'Style', 'text', ...
    'String', sprintf(['LEADERBOARD RISCHIO DEGRADO - Include Trend Base e Aggravante Laterale (Max 100). ' ...
                       'Esclusi difetti con < %d passaggi o < %d giorni storici.'], ...
                      C.IPI_MIN_RUNS, C.IPI_MIN_DAYS), ...
    'Units', 'normalized', 'Position', [0.05 0.92 0.9 0.05], ...
    'FontSize', 11, 'FontWeight', 'bold', 'BackgroundColor', 'w', 'ForegroundColor', [0.6 0 0]);

   
    tab_data = cell(length(SortedIpi), 12);
    for i = 1:length(SortedIpi)
        tab_data{i,1} = i; 
        tab_data{i,2} = SortedIpi(i).ID;
        
        ipi_val = SortedIpi(i).IPI;
        if ipi_val >= 75, col_hex = '#CC0000';
        elseif ipi_val >= 50, col_hex = '#FF8000';
        elseif ipi_val >= 25, col_hex = '#E6C300';
        else, col_hex = '#009900'; end
        
        tab_data{i,3} = ['<html><font color="', col_hex, '"><b>', num2str(ipi_val), ' / 100</b></font></html>'];
        
        tab_data{i,4}  = sprintf('%.1f', SortedIpi(i).SAbsolute); % NUOVA COLONNA
        tab_data{i,5}  = sprintf('%.1f', SortedIpi(i).STrend);
        tab_data{i,6}  = sprintf('+%.1f', SortedIpi(i).BonusLat);
        tab_data{i,7}  = sprintf('%+.1f %%', SortedIpi(i).IncPerc);
        tab_data{i,8}  = sprintf('%.1f', SortedIpi(i).RecentRMS);
        tab_data{i,9}  = sprintf('%.1f (T:%.1f + E:%.1f)', SortedIpi(i).BonusPCA, SortedIpi(i).PcaBonusTrend, SortedIpi(i).PcaBonusExcur);
        tab_data{i,10} = sprintf('%+.1f %%  (#%d)', SortedIpi(i).PcaIncPerc, SortedIpi(i).PcaExcursions);
        tab_data{i,11} = sprintf('%.1f', SortedIpi(i).BonusIA);
        if isnan(SortedIpi(i).IAAccRecent)
            tab_data{i,12} = 'N/A';
        else
            tab_data{i,12} = sprintf('%.1f %%', SortedIpi(i).IAAccRecent);
        end
    end
    
    col_names = {'Pos.', 'ID Difetto (PK)', 'IPI Score Totale', ...
                 'P.ti Assoluti (Max 50)', 'P.ti Trend (Max 50)', 'P.ti Laterale (Max 30)', ...
                 'Incremento Severità', 'RMS Recente [m/s^2]', ...
                 'Punti PCA (T+E)', 'Inc. PCA % (#excur)', ...
                 'Bonus IA (Max 20)', 'Acc. Recente IA'};
                 
    t_ipi = uitable('Parent', tab_ipi, 'Data', tab_data, 'ColumnName', col_names, ...
        'Units', 'normalized', 'Position', [0.05 0.35 0.9 0.55], 'RowName', [], ...
        'ColumnWidth', {40, 140, 120, 140, 140, 140, 130, 140}, 'FontSize', 10);
    % =========================================================
    % NUOVO: MINI-CLASSIFICHE TOP 5 (Sotto la classifica IPI)
    % =========================================================
    
    % 1. Top 5 Verticale
    [~, sort_v] = sort([ValidIpiData.MaxVert], 'descend');
    top5_v = ValidIpiData(sort_v(1:min(5, end)));
    data_v = cell(length(top5_v), 3);
    for k = 1:length(top5_v)
        data_v{k,1} = k; data_v{k,2} = top5_v(k).ID; data_v{k,3} = sprintf('%.1f', top5_v(k).MaxVert);
    end
    
    % 2. Top 5 Laterale
    [~, sort_l] = sort([ValidIpiData.MaxLat], 'descend');
    top5_l = ValidIpiData(sort_l(1:min(5, end)));
    data_l = cell(length(top5_l), 3);
    for k = 1:length(top5_l)
        data_l{k,1} = k; data_l{k,2} = top5_l(k).ID; data_l{k,3} = sprintf('%.1f', top5_l(k).MaxLat);
    end
    
    % 3. Top 5 Peggioramento
    [~, sort_p] = sort([ValidIpiData.IncPerc], 'descend');
    top5_p = ValidIpiData(sort_p(1:min(5, end)));
    data_p = cell(length(top5_p), 3);
    for k = 1:length(top5_p)
        data_p{k,1} = k; data_p{k,2} = top5_p(k).ID; data_p{k,3} = sprintf('%+.1f %%', top5_p(k).IncPerc);
    end
    
    % --- Disegno UI per le Top 5 ---
    w_t = 0.28; gap_t = 0.03;
    
    % Verticale
    uicontrol('Parent', tab_ipi, 'Style', 'text', 'String', '🔴 TOP 5 - Max RMS Verticale', ...
        'Units', 'normalized', 'Position', [0.05 0.28 w_t 0.04], 'FontWeight', 'bold', 'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    uitable('Parent', tab_ipi, 'Data', data_v, 'ColumnName', {'Pos', 'PK', 'RMS Vert'}, ...
        'Units', 'normalized', 'Position', [0.05 0.05 w_t 0.23], 'RowName', [], 'ColumnWidth', {35, 120, 80});
        
    % Laterale
    uicontrol('Parent', tab_ipi, 'Style', 'text', 'String', '🟠 TOP 5 - Max RMS Laterale', ...
        'Units', 'normalized', 'Position', [0.05+w_t+gap_t 0.28 w_t 0.04], 'FontWeight', 'bold', 'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    uitable('Parent', tab_ipi, 'Data', data_l, 'ColumnName', {'Pos', 'PK', 'RMS Lat'}, ...
        'Units', 'normalized', 'Position', [0.05+w_t+gap_t 0.05 w_t 0.23], 'RowName', [], 'ColumnWidth', {35, 120, 80});
        
    % Peggioramento
    uicontrol('Parent', tab_ipi, 'Style', 'text', 'String', '📉 TOP 5 - Maggior Peggioramento', ...
        'Units', 'normalized', 'Position', [0.05+2*(w_t+gap_t) 0.28 w_t 0.04], 'FontWeight', 'bold', 'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    uitable('Parent', tab_ipi, 'Data', data_p, 'ColumnName', {'Pos', 'PK', 'Trend %'}, ...
        'Units', 'normalized', 'Position', [0.05+2*(w_t+gap_t) 0.05 w_t 0.23], 'RowName', [], 'ColumnWidth', {35, 120, 80});

    % Datatip Globale
end

% % --- Funzione Helper per Disegnare la Griglia 2x2 ---
% function draw_4_panel_stats(parent_tab, vF, vR, group_name, meta_list,defectIDs)
%     mx = max([vF; vR]) * 1.1;
%     if mx < 5, mx = 5; end
%     PERCENTILI = [90, 95, 98, 99]; colors_p = lines(4);
% 
% % 1. SCATTER PLOT RAGGRUPPATO PER COLORE
%     ax1 = subplot(2, 2, 1, 'Parent', parent_tab); hold(ax1, 'on'); grid(ax1, 'on');
% 
%     % Usiamo l'ID del difetto per colorare i punti
%     % 'defectIDs' assegna un colore diverso a ogni difetto
%     h1 = scatter(ax1, vF, vR, 25, defectIDs, 'filled', ...
%         'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.5);
% 
%     colormap(ax1, turbo(max(defectIDs))); % Turbo o jet offrono molti colori distinti
% 
%     plot(ax1, [0 mx], [0 mx], 'k--', 'LineWidth', 1); % Bisettrice
%     axis(ax1, 'square'); xlim(ax1, [0 mx]); ylim(ax1, [0 mx]);
% 
%     % 2. WEIBULL
%     ax2 = subplot(2, 2, 2, 'Parent', parent_tab); hold(ax2, 'on'); grid(ax2, 'on');
%     histogram(ax2, vF, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'EdgeColor', 'r', 'LineWidth', 1.5, 'DisplayName', 'Front');
%     histogram(ax2, vR, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'EdgeColor', 'b', 'LineWidth', 1.5, 'DisplayName', 'Rear');
%     try pdF=fitdist(vF,'Weibull'); xg=linspace(0,mx,200); plot(ax2, xg,pdf(pdF,xg),'r:','LineWidth',2,'DisplayName','Fit F'); catch, end
%     try pdR=fitdist(vR,'Weibull'); xg=linspace(0,mx,200); plot(ax2, xg,pdf(pdR,xg),'b:','LineWidth',2,'DisplayName','Fit R'); catch, end
%     xlim(ax2, [0 mx]); 
%     xlabel(ax2, 'Severità [m/s^2]'); ylabel(ax2, 'Densità di Probabilità'); 
%     title(ax2, 'Distribuzioni Weibull Fit'); legend(ax2, 'Location', 'best');
% 
%     % 3. SOGLIE INDIPENDENTI
%     ax3 = subplot(2, 2, 3, 'Parent', parent_tab); hold(ax3, 'on'); grid(ax3, 'on');
%     h3 = scatter(ax3, vF, vR, 15, 'k', 'o', 'MarkerFaceAlpha', 0.3, 'Tag', 'DefectScatter');
%     set(h3, 'UserData', meta_list);
%     P_F = prctile(vF, PERCENTILI); P_R = prctile(vR, PERCENTILI);
%     for i=1:length(PERCENTILI)
%         xline(ax3, P_F(i), '--', 'Color', colors_p(i,:), 'LineWidth', 1.5);
%         yline(ax3, P_R(i), '--', 'Color', colors_p(i,:), 'LineWidth', 1.5);
%     end
%     axis(ax3, 'square'); xlim(ax3, [0 mx]); ylim(ax3, [0 mx]); 
%     xlabel(ax3, ['Ant (' group_name ') [m/s^2]']); ylabel(ax3, ['Pos (' group_name ') [m/s^2]']); 
%     title(ax3, 'Soglie Indipendenti');
% 
%     % 4. SOGLIE COMBINATE
%     ax4 = subplot(2, 2, 4, 'Parent', parent_tab); hold(ax4, 'on'); grid(ax4, 'on');
%     h4 = scatter(ax4, vF, vR, 15, 'k', 'o', 'MarkerFaceAlpha', 0.3, 'Tag', 'DefectScatter');
%     set(h4, 'UserData', meta_list);
%     Mags = sqrt(vF.^2 + vR.^2); P_Rad = prctile(Mags, PERCENTILI); theta = linspace(0, pi/2, 100);
%     for i=1:length(PERCENTILI)
%         plot(ax4, P_Rad(i)*cos(theta), P_Rad(i)*sin(theta), 'Color', colors_p(i,:), 'LineWidth', 2, 'DisplayName', sprintf('%d%%', PERCENTILI(i)));
%     end
%     plot(ax4, [0 mx], [0 mx], 'k:', 'HandleVisibility', 'off');
%     axis(ax4, 'square'); xlim(ax4, [0 mx]); ylim(ax4, [0 mx]); 
%     xlabel(ax4, ['Ant (' group_name ') [m/s^2]']); ylabel(ax4, ['Pos (' group_name ') [m/s^2]']); 
%     title(ax4, 'Soglie Combinate'); legend(ax4, 'Location', 'bestoutside');
% end



% --- Funzione Helper per Disegnare la Griglia 2x2 ---
function draw_4_panel_stats(parent_tab, vF, vR, group_name, meta_list, defectIDs)
    mx = max([vF; vR]) * 1.1;
    if mx < 5, mx = 5; end
    PERCENTILI = [90, 95, 98, 99]; colors_p = lines(4);
    
    % --- FILTRO ASIMMETRIA ---
    ratio = vF ./ max(vR, 1e-6);
    asym_mask = (ratio > 1.5) | (ratio < 0.66); 
    sym_mask = ~asym_mask;
    
    % 1. IDENTIFICAZIONE OUTLIER E CREAZIONE COLORI
    unique_asym_ids = unique(defectIDs(asym_mask));
    n_asym = length(unique_asym_ids);
    cmap = turbo(max(1, n_asym)); % Genera una palette di colori ben distinti
    
    % Prepariamo gli assi in anticipo per poterci disegnare dentro durante il loop
    ax1 = subplot(2, 2, 1, 'Parent', parent_tab); hold(ax1, 'on'); grid(ax1, 'on');
    ax3 = subplot(2, 2, 3, 'Parent', parent_tab); hold(ax3, 'on'); grid(ax3, 'on');
    ax4 = subplot(2, 2, 4, 'Parent', parent_tab); hold(ax4, 'on'); grid(ax4, 'on');
    
    % Disegna prima la massa di punti simmetrici (sfondo grigio) su tutti gli assi
    if any(sym_mask)
        scatter(ax1, vF(sym_mask), vR(sym_mask), 15, [0.8 0.8 0.8], 'filled', 'MarkerFaceAlpha', 0.2, 'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');
        scatter(ax3, vF(sym_mask), vR(sym_mask), 10, [0.8 0.8 0.8], 'filled', 'MarkerFaceAlpha', 0.2, 'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');
        scatter(ax4, vF(sym_mask), vR(sym_mask), 10, [0.8 0.8 0.8], 'filled', 'MarkerFaceAlpha', 0.2, 'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');
    end
    
    % Variabili per salvare la legenda di ax1
    leg_handles = gobjects(0);
    leg_labels = {};
    
    % 2. LOOP SUI DIFETTI ASIMMETRICI (Assegna colore e PK)
    for k = 1:n_asym
        uid = unique_asym_ids(k);
        idx_mask = (defectIDs == uid) & asym_mask;
        
        % Estrai la PK dai metadati per usarla nella legenda
        idx_first = find(idx_mask, 1);
        meta_str = meta_list{idx_first};
        tk = regexp(meta_str, 'PK:\s*(\S+)', 'tokens');
        if ~isempty(tk), pk_str = tk{1}{1}; else, pk_str = sprintf('ID %d', uid); end
        
        color_k = cmap(k, :); % Colore fisso per questo specifico difetto
        
        % Disegna su ax1 (Con Legenda)
        h1 = scatter(ax1, vF(idx_mask), vR(idx_mask), 35, color_k, 'filled', ...
            'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.8, 'Tag', 'DefectScatter', 'DisplayName', pk_str);
        set(h1, 'UserData', meta_list(idx_mask));
        leg_handles(end+1) = h1;
        leg_labels{end+1} = pk_str;
        
        % Disegna su ax3 (Stesso colore, senza duplicare la legenda)
        h3 = scatter(ax3, vF(idx_mask), vR(idx_mask), 25, color_k, 'filled', ...
            'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.7, 'Tag', 'DefectScatter', 'HandleVisibility', 'off');
        set(h3, 'UserData', meta_list(idx_mask));
        
        % Disegna su ax4 (Stesso colore, senza duplicare la legenda)
        h4 = scatter(ax4, vF(idx_mask), vR(idx_mask), 25, color_k, 'filled', ...
            'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.7, 'Tag', 'DefectScatter', 'HandleVisibility', 'off');
        set(h4, 'UserData', meta_list(idx_mask));
    end
    
    % --- SETUP FINALE AX1 ---
    plot(ax1, [0 mx], [0 mx], 'k--', 'LineWidth', 1, 'HandleVisibility', 'off'); % Bisettrice
    axis(ax1, 'square'); xlim(ax1, [0 mx]); ylim(ax1, [0 mx]);
    xlabel(ax1, ['Ant (' group_name ') [m/s^2]']); ylabel(ax1, ['Pos (' group_name ') [m/s^2]']);
    title(ax1, 'Confronto Scatter (Outlier Evidenziati)');
    
    % Costruzione della Legenda (solo se ci sono outlier)
    if n_asym > 0
        lgd = legend(ax1, leg_handles, leg_labels, 'Location', 'bestoutside', 'Interpreter', 'none');
        title(lgd, 'PK ');
        if n_asym > 15
            lgd.NumColumns = ceil(n_asym / 15); % Divide in colonne se ci sono troppi difetti
        end
    end
    
    % --- 2. WEIBULL (ax2) ---
    ax2 = subplot(2, 2, 2, 'Parent', parent_tab); hold(ax2, 'on'); grid(ax2, 'on');
    histogram(ax2, vF, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'EdgeColor', 'r', 'LineWidth', 1.5, 'DisplayName', 'Front');
    histogram(ax2, vR, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'EdgeColor', 'b', 'LineWidth', 1.5, 'DisplayName', 'Rear');
    try pdF=fitdist(vF,'Weibull'); xg=linspace(0,mx,200); plot(ax2, xg,pdf(pdF,xg),'r:','LineWidth',2,'DisplayName','Fit F'); catch, end
    try pdR=fitdist(vR,'Weibull'); xg=linspace(0,mx,200); plot(ax2, xg,pdf(pdR,xg),'b:','LineWidth',2,'DisplayName','Fit R'); catch, end
    xlim(ax2, [0 mx]); 
    xlabel(ax2, 'Severità [m/s^2]'); ylabel(ax2, 'Densità di Probabilità'); 
    title(ax2, 'Distribuzioni Weibull Fit'); legend(ax2, 'Location', 'best');
    
    % --- SETUP FINALE AX3 ---
    P_F = prctile(vF, PERCENTILI); P_R = prctile(vR, PERCENTILI);
    for i=1:length(PERCENTILI)
        xline(ax3, P_F(i), '--', 'Color', colors_p(i,:), 'LineWidth', 1.5, 'HandleVisibility', 'off');
        yline(ax3, P_R(i), '--', 'Color', colors_p(i,:), 'LineWidth', 1.5, 'HandleVisibility', 'off');
    end
    axis(ax3, 'square'); xlim(ax3, [0 mx]); ylim(ax3, [0 mx]); 
    xlabel(ax3, ['Ant (' group_name ') [m/s^2]']); ylabel(ax3, ['Pos (' group_name ') [m/s^2]']); 
    title(ax3, 'Soglie Indipendenti');
    
    % --- SETUP FINALE AX4 ---
    Mags = sqrt(vF.^2 + vR.^2); P_Rad = prctile(Mags, PERCENTILI); theta = linspace(0, pi/2, 100);
    for i=1:length(PERCENTILI)
        plot(ax4, P_Rad(i)*cos(theta), P_Rad(i)*sin(theta), 'Color', colors_p(i,:), 'LineWidth', 2, 'DisplayName', sprintf('%d%%', PERCENTILI(i)));
    end
    plot(ax4, [0 mx], [0 mx], 'k:', 'HandleVisibility', 'off');
    axis(ax4, 'square'); xlim(ax4, [0 mx]); ylim(ax4, [0 mx]); 
    xlabel(ax4, ['Ant (' group_name ') [m/s^2]']); ylabel(ax4, ['Pos (' group_name ') [m/s^2]']); 
    title(ax4, 'Soglie Combinate'); legend(ax4, 'Location', 'bestoutside');
end


% --- NUOVO HELPER TOOLTIP ROBUSTO ---
function txt = custom_datatip_robust(~, event_obj)
    target = event_obj.Target;
    pos = event_obj.Position;
    
    if ~isprop(target, 'Tag') || ~strcmp(target.Tag, 'DefectScatter')
        txt = {['X: ', num2str(pos(1), '%.2f')], ['Y: ', num2str(pos(2), '%.2f')]};
        return;
    end
    
    idx = event_obj.DataIndex;
    meta_list = get(target, 'UserData'); % Legge i metadati salvati nello specifico grafico
    
    if iscell(meta_list) && idx <= length(meta_list)
        pk_str = meta_list{idx};
    else
        pk_str = 'N/A';
    end
    
    txt = {pk_str, ['Ant: ', num2str(pos(1), '%.2f')], ['Pos: ', num2str(pos(2), '%.2f')]};
end


% --- Funzione Supporto Grafici Statistici (Modificata per usare i Tab) ---
function draw_statistical_appendix(vF, vR, pks, mx, tabgp, f_main)
    PERCENTILI = [90, 95, 98, 99]; colors_p = lines(4);
    
    % --- TAB 2: Weibull ---
    tab_weibull = uitab(tabgp, 'Title', 'Distribuzioni Weibull');
    ax_w = axes('Parent', tab_weibull); hold(ax_w, 'on');
    
    histogram(ax_w, vF, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'EdgeColor', 'r', 'LineWidth', 1.5, 'DisplayName', 'Front');
    histogram(ax_w, vR, 'Normalization', 'pdf', 'DisplayStyle', 'stairs', 'EdgeColor', 'b', 'LineWidth', 1.5, 'DisplayName', 'Rear');
    try pdF=fitdist(vF,'Weibull'); xg=linspace(0,mx,200); plot(ax_w, xg,pdf(pdF,xg),'r:','LineWidth',2,'DisplayName','Fit F'); catch, end
    try pdR=fitdist(vR,'Weibull'); xg=linspace(0,mx,200); plot(ax_w, xg,pdf(pdR,xg),'b:','LineWidth',2,'DisplayName','Fit R'); catch, end
    
    grid(ax_w, 'on'); xlabel(ax_w, 'RMS'); title(ax_w, 'Weibull Fit'); xlim(ax_w, [0 mx]); legend(ax_w, 'Location','best');
    
    % --- TAB 3: Soglie Indipendenti ---
    tab_indep = uitab(tabgp, 'Title', 'Soglie Indipendenti');
    ax_i = axes('Parent', tab_indep); hold(ax_i, 'on');
    
    scatter(ax_i, vF, vR, 15, 'k', 'o', 'MarkerFaceAlpha', 0.3, 'Tag', 'DefectScatter');
    P_F = prctile(vF, PERCENTILI); P_R = prctile(vR, PERCENTILI);
    for i=1:length(PERCENTILI)
        xline(ax_i, P_F(i), '--', 'Color', colors_p(i,:), 'LineWidth', 1.5, 'DisplayName', sprintf('%d%%', PERCENTILI(i)));
        yline(ax_i, P_R(i), '--', 'Color', colors_p(i,:), 'LineWidth', 1.5, 'HandleVisibility', 'off');
    end
    
    grid(ax_i, 'on'); axis(ax_i, 'square'); xlim(ax_i, [0 mx]); ylim(ax_i, [0 mx]); 
    xlabel(ax_i, 'Ant'); ylabel(ax_i, 'Pos'); title(ax_i, 'Soglie Indipendenti'); legend(ax_i, 'Location','bestoutside');
    
    % --- TAB 4: Soglie Circolari ---
    tab_comb = uitab(tabgp, 'Title', 'Soglie Combinate');
    ax_c = axes('Parent', tab_comb); hold(ax_c, 'on');
    
    scatter(ax_c, vF, vR, 15, 'k', 'o', 'MarkerFaceAlpha', 0.3, 'Tag', 'DefectScatter');
    Mags = sqrt(vF.^2 + vR.^2); P_Rad = prctile(Mags, PERCENTILI); theta = linspace(0, pi/2, 100);
    for i=1:length(PERCENTILI)
        plot(ax_c, P_Rad(i)*cos(theta), P_Rad(i)*sin(theta), 'Color', colors_p(i,:), 'LineWidth', 2, 'DisplayName', sprintf('%d%%', PERCENTILI(i)));
    end
    plot(ax_c, [0 mx], [0 mx], 'k:', 'HandleVisibility', 'off');
    
    grid(ax_c, 'on'); axis(ax_c, 'square'); xlim(ax_c, [0 mx]); ylim(ax_c, [0 mx]); 
    xlabel(ax_c, 'Ant'); ylabel(ax_c, 'Pos'); title(ax_c, 'Soglie Combinate'); legend(ax_c, 'Location','bestoutside');
    
    % --- IMPOSTAZIONE DATATIP GLOBALE ---
    % Applichiamo il datacursor all'intera figura una sola volta
    dcm_global = datacursormode(f_main); 
    set(dcm_global, 'Enable', 'on', 'UpdateFcn', @(obj,evt) custom_datatip(obj,evt, pks));
end





function update_signals_only(h)
    % Verifica dati
    if isempty(h.DB) || isempty(h.CurrDefectIdx), return; end
    Defect = h.DB(h.CurrDefectIdx); 
    RunData = Defect.History(h.CurrRunIdx); 
    pk_center = Defect.Avg_Pos;
    

    % =========================================================
    % NUOVO: Estrazione Velocità e Curvatura per Titolo Pannello
    % =========================================================
    v_run = NaN;
    if isfield(RunData, 'Speed') && ~isempty(RunData.Speed)
        v_run = double(RunData.Speed(1));
    elseif isfield(RunData, 'Data') && isfield(RunData.Data, 'Speed') && ~isempty(RunData.Data.Speed)
        v_run = double(RunData.Data.Speed(1));
    end
    if isnan(v_run)
        str_vel = 'N/D'; 
    else
        str_vel = sprintf('%.0f km/h', v_run); 
    end
    
    c_val = NaN;
    if isfield(RunData, 'Curve') && ~isempty(RunData.Curve) && isnumeric(RunData.Curve)
        c_val = double(RunData.Curve(1));
    elseif isfield(RunData, 'Data') && isfield(RunData.Data, 'Curve') && ~isempty(RunData.Data.Curve)
        c_val = double(RunData.Data.Curve(1));
    end
    if isnan(c_val) || c_val == 0
        str_curv = 'N/D';                        % campo 'curve' assente nel sorgente
    elseif (1/c_val) > 5000
        str_curv = 'Rettilineo';                 % curvatura trascurabile (R > 5 km)
    else
        str_curv = sprintf('R %.0f m', 1/c_val); % Data.Curve è curvatura (1/m) -> raggio
    end
    
    % Aggiorna dinamicamente il titolo del pannello
    set(h.Axes(1).Parent, 'Title', sprintf('Dettaglio Passaggi   [ Velocità: %s  |  Curvatura: %s ]', str_vel, str_curv));
    % =========================================================
    % Recupera dati per decisione (usiamo FILT o RAW)
    if isfield(RunData.Data, 'Filt'), DataCheck = RunData.Data.Filt;
    else, DataCheck = RunData.Data.Raw; end
    
    % --- LOGICA DECISIONALE LATERALE ---
    rms_lat_dx = 0; rms_lat_sx = 0;
    
    % Controlliamo l'energia RMS per capire quale sensore era attivo
    if isfield(DataCheck, 'right_sensor_front_lat') && ~isempty(DataCheck.right_sensor_front_lat)
        rms_lat_dx = rms(double(DataCheck.right_sensor_front_lat)); 
    end
    if isfield(DataCheck, 'left_sensor_front_lat') && ~isempty(DataCheck.left_sensor_front_lat)
        rms_lat_sx = rms(double(DataCheck.left_sensor_front_lat)); 
    end
    
    % Default: Mostra DX (Forward)
    lat_sens_front = 'right_sensor_front_lat';
    lat_sens_rear  = 'right_sensor_rear_lat';
    lat_title_base = 'Lat DX';
    status_str     = 'MARCIA AVANTI (Lat DX Attivo)';
    status_col     = [0 0.6 0]; % Verde scuro
    
    % Se SX ha più energia di DX -> Mostra SX (Backward)
    if rms_lat_sx > rms_lat_dx
        lat_sens_front = 'left_sensor_front_lat';
        lat_sens_rear  = 'left_sensor_rear_lat';
        lat_title_base = 'Lat SX';
        status_str     = 'MARCIA INDIETRO (Lat SX Attivo)';
        status_col     = [0.8 0 0]; % Rosso scuro
    elseif rms_lat_sx == 0 && rms_lat_dx == 0
        status_str     = 'NO DATI LATERALI';
        status_col     = [0.5 0.5 0.5]; % Grigio
    end
    
    % Aggiorna l'etichetta visiva
    set(h.LblLatStatus, 'String', status_str, 'ForegroundColor', status_col);
    
    % --- CONFIGURAZIONE GRAFICI ---
    % I primi 4 sono fissi, gli ultimi 2 sono dinamici
    PlotConfig = {
        'left_sensor_front',  'Vert SX (Front)';
        'left_sensor_rear',   'Vert SX (Rear)';
        'right_sensor_front', 'Vert DX (Front)';
        'right_sensor_rear',  'Vert DX (Rear)';
        lat_sens_front,       [lat_title_base ' (Front)'];
        lat_sens_rear,        [lat_title_base ' (Rear)']
    };
    
    % --- LOOP DI PLOT ---
    for i = 1:6
        ax = h.Axes(i); 
        cla(ax); 
        
        sens_name  = PlotConfig{i, 1};
        sens_title = PlotConfig{i, 2};
        y = [];
        col = [0 0.4 0.8]; % Default: BLU (Filt)

        % Estrazione dati Raw/Filt
       rawtime_rel = [];   % asse dedicato per il RAW TIME (lunghezza diversa)
        if strcmp(h.Mode, 'Raw')
            if isfield(RunData.Data, 'RawTime') && isfield(RunData.Data.RawTime, sens_name)
                y = double(RunData.Data.RawTime.(sens_name));
                y = y - mean(y, 'omitnan');
                col = [0.4 0.4 0.4];        % GRIGIO per RAW (time)
                if isfield(RunData.Data, 'RawTimeAxis') && length(RunData.Data.RawTimeAxis) == length(y)
                    rawtime_rel = double(RunData.Data.RawTimeAxis(:).');
                end
            elseif isfield(RunData.Data, 'Raw') && isfield(RunData.Data.Raw, sens_name)
                y = double(RunData.Data.Raw.(sens_name));
                y = y - mean(y, 'omitnan');
                col = [0.4 0.4 0.4];
            else
                fprintf('ATTENZIONE: Raw non trovato per %s! Ripiego su Filt.\n', sens_name);
                y = double(RunData.Data.Filt.(sens_name));
                col = [0 0.4 0.8];
            end
        else
            % Modalità Filt
            if isfield(RunData.Data, 'Filt') && isfield(RunData.Data.Filt, sens_name)
                y = double(RunData.Data.Filt.(sens_name));
                col = [0 0.4 0.8];          % BLU per Filt
            end
        end

        if ~isempty(y)
            % ... resto del codice di plotting che usa 'col' ...
            c_pos_vero = pk_center;
            
            if ~isempty(rawtime_rel)
                x = c_pos_vero + rawtime_rel;
            elseif isfield(RunData.Data, 'RelativeAxis') && length(RunData.Data.RelativeAxis) == length(y)
                x = c_pos_vero + double(RunData.Data.RelativeAxis(:).');
            else
                half_win = h.CFG.WINDOW_SIZE;
                x = linspace(c_pos_vero - half_win, c_pos_vero + half_win, length(y));
            end
            
            y_max = max(y); y_min = min(y); range_y = y_max - y_min; 
            if range_y < 1e-6, range_y = 1; end 
            y_lims = [y_min - 0.2*range_y, y_max + 0.3*range_y];
            
            set(ax, 'YLim', y_lims, 'XLim', [min(x), max(x)]);
            ax.XAxis.Exponent = 0;
            try draw_infra_overlay(ax, h.InfraMap, [min(x), max(x)]); catch, end

            hold(ax, 'on'); 
            plot(ax, x, y, 'Color', col, 'LineWidth', 0.8); 
            xline(ax, pk_center, 'r--', 'LineWidth', 1.2); 
            grid(ax, 'on'); xtickformat(ax, '%.1f');
        else
            text(ax, 0.5, 0.5, 'N/A', 'Color', 'r', 'HorizontalAlignment', 'center');
        end
        title(ax, sens_title, 'FontSize', 8, 'FontWeight', 'bold');
    end
end


function update_top_plots(h)
    % 1. CONTROLLI DI SICUREZZA
    if isempty(h.DB) || isempty(h.CurrDefectIdx), return; end
    
    Defect = h.DB(h.CurrDefectIdx); 
    RunInfo = Defect.History(h.CurrRunIdx);
    
    ax_ctx = h.AxContext; 
    ax_rms = h.AxCfar;
    
    cla(ax_ctx); legend(ax_ctx, 'off');
    cla(ax_rms); legend(ax_rms, 'off');
    
    % 2. CARICAMENTO DATI
    fName = char(RunInfo.RunName); 
    parts = split(fName, '_'); 
    if length(parts) < 2, return; end
    
    date_folder = [parts{1} '_' parts{2}]; 
    full_path = fullfile(h.ParentFolder, h.CurrentTrackName, date_folder, [fName '.mat']);
    
    if ~exist(full_path, 'file'), return; end
    try
        d = load(full_path, 'section_extracted'); 
        data = d.section_extracted;
        
        % 3. SELEZIONE SENSORI
        if isfield(h, 'GroupMap') && isfield(h, 'CurrentGroup')
            try
                groupSensors = h.GroupMap(h.CurrentGroup);
                s_front = groupSensors{1}; s_rear = groupSensors{2};
            catch, s_front = 'left_sensor_front'; s_rear = 'left_sensor_rear'; end
        else
            s_front = 'left_sensor_front'; s_rear = 'left_sensor_rear';
        end
        
        raw_F = double(data.(s_front)); 
        raw_R = double(data.(s_rear));
        space = double(data.space_neutral);
        
        % 4. VARIABILI BASE E GESTIONE ASSI FISICI NATIVI
        center_pk = Defect.Avg_Pos;
        C = h.CFG;
        % Allineamento al filtraggio del DB (analyze_and_extract, ONLY_JOINTS=false)
        SPATIAL_RES = 0.004;   % era C.SPATIAL_RES (0.030)
        L_MAX_DB    = 15;      % era C.L_MAX (0.5)
        L_MIN_DB    = 0.01;    % era C.L_MIN_QUIET (0.07)
        L = min([length(raw_F), length(raw_R), length(space)]);
        raw_F = raw_F(1:L); raw_R = raw_R(1:L); space = space(1:L);

        % Leggiamo il MacroShift nativo
        macro_shift = 0;
        if isfield(RunInfo, 'MacroShift') && ~isempty(RunInfo.MacroShift)
            macro_shift = RunInfo.MacroShift;
        end

        space_shifted = space + macro_shift;
        
        if isfield(data, 'space_front') && isfield(data, 'space_back')
            axis_F_raw = double(data.space_front(1:L)) + macro_shift;
            axis_R_raw = double(data.space_back(1:L)) + macro_shift;
        elseif isfield(data, 'space_parameters')
            pF = 0; pR = 0;
            if isfield(data.space_parameters, 'front'), pF = data.space_parameters.front; end
            if isfield(data.space_parameters, 'back'),  pR = data.space_parameters.back; end
            axis_F_raw = space_shifted + pF;
            axis_R_raw = space_shifted + pR;
        else
            axis_F_raw = space_shifted;
            axis_R_raw = space_shifted;
        end

        % =========================================================
        % PIPELINE DI FILTRAGGIO SECONDARIO
        % =========================================================
        MARGIN_P2 = 100;
        idx_p2 = space_shifted >= (center_pk - MARGIN_P2) & space_shifted <= (center_pk + MARGIN_P2);
        if sum(idx_p2) < 100
            idx_p2 = true(size(space_shifted));
        end
        raw_F_p2     = raw_F(idx_p2);
        raw_R_p2     = raw_R(idx_p2);
        axis_F_p2    = axis_F_raw(idx_p2);
        axis_R_p2    = axis_R_raw(idx_p2);
        space_neu_p2 = space_shifted(idx_p2);

        raw_F_p2 = raw_F_p2 - mean(raw_F_p2, 'omitnan');
        raw_R_p2 = raw_R_p2 - mean(raw_R_p2, 'omitnan');

        [bT, aT] = butter(2, [C.fmin, C.fmax]/(C.fs_time/2), 'bandpass');
        fT_F = filtfilt(bT, aT, raw_F_p2);
        fT_R = filtfilt(bT, aT, raw_R_p2);

        c_space_full = (ceil(min(space_neu_p2)/SPATIAL_RES) : floor(max(space_neu_p2)/SPATIAL_RES)) * SPATIAL_RES;

        [uF, iF] = unique(axis_F_p2, 'stable');
        [uR, iR] = unique(axis_R_p2, 'stable');
        sF_sp = interp1(uF, fT_F(iF), c_space_full, 'linear', 0);
        sR_sp = interp1(uR, fT_R(iR), c_space_full, 'linear', 0);

        fs_s = 1/SPATIAL_RES;
        [bQ, aQ] = butter(2, [1/L_MAX_DB, 1/L_MIN_DB]/(fs_s/2), 'bandpass');
        filt_F_full = filtfilt(bQ, aQ, sF_sp);
        filt_R_full = filtfilt(bQ, aQ, sR_sp);

        idx_ctx = c_space_full >= (center_pk - 52) & c_space_full <= (center_pk + 52);
        filt_F = filt_F_full(idx_ctx);
        filt_R = filt_R_full(idx_ctx);
        common_space = c_space_full(idx_ctx);
       
        % =========================================================
        % ALLINEAMENTO AL DB (stesso ancoraggio del Dettaglio Passaggi)
        % Niente ricerca di picco indipendente: agganciamo il contesto
        % al segnale GIÀ allineato salvato nel database, così la linea
        % rossa cade sullo stesso punto dei grafici in basso.
        % =========================================================
        try
            if isfield(RunInfo, 'Data') && isfield(RunInfo.Data, 'RelativeAxis') ...
                    && isfield(RunInfo.Data, 'Filt') && isfield(RunInfo.Data.Filt, s_front)
                db_axis = center_pk + double(RunInfo.Data.RelativeAxis(:).');
                db_F    = double(RunInfo.Data.Filt.(s_front)(:).');
                [db_axis_u, iu] = unique(db_axis, 'stable');
                db_on_ctx = interp1(db_axis_u, db_F(iu), common_space, 'linear', 0);

                max_lag = round(4.5 / SPATIAL_RES);
                [xc, lags] = xcorr(abs(filt_F(:).'), abs(db_on_ctx(:).'), max_lag);
                [xc_max, im] = max(xc);
                if isfinite(xc_max) && xc_max > 0
                    common_space = common_space - lags(im) * SPATIAL_RES;
                end
            end
        catch
            % fallback: nessuno shift, ci si fida del macro/geo allineamento
        end
        
        % =========================================================
        % CALCOLO RMS PER GRAFICO CFAR (Il blocco che mancava!)
        % =========================================================
        win_fast = round(C.RMS_WIN_FAST / SPATIAL_RES);
        win_slow = round(C.RMS_WIN_SLOW / SPATIAL_RES);

        rms_F = sqrt(movmean(filt_F.^2, win_fast));
        rms_R = sqrt(movmean(filt_R.^2, win_fast));

        % Soglia dinamica PER SENSORE: max(movmean(env, slow)*MUL, 0.05)
        th_F = max(movmean(rms_F, win_slow) * C.RMS_MUL, 0.05);
        th_R = max(movmean(rms_R, win_slow) * C.RMS_MUL, 0.05);

        % =========================================================
        % PLOT 1: CONTESTO (Segnale FILTRATO RICALCOLATO)
        % =========================================================
        hold(ax_ctx, 'on'); grid(ax_ctx, 'on');
        
        show_front = strcmp(h.ViewMode, 'Both') || strcmp(h.ViewMode, 'Front');
        show_rear  = strcmp(h.ViewMode, 'Both') || strcmp(h.ViewMode, 'Rear');

        if show_front
            plot(ax_ctx, common_space, filt_F, 'Color', [0 0.4 0.8], 'LineWidth', 0.8, 'DisplayName', 'Front');
        end
        if show_rear
            plot(ax_ctx, common_space, filt_R, 'Color', [0.8 0 0], 'LineWidth', 0.8, 'DisplayName', 'Rear');
        end
        
        % --- Sostituisci il vecchio blocco xlim con questo ---
        xline(ax_ctx, center_pk, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Centro Picco');

        % Svincoliamo dalla window size: 10m per lato = 20 metri totali di contesto
        half_win_ctx = 10.0; 
        x_lims = [center_pk - half_win_ctx, center_pk + half_win_ctx];
        xlim(ax_ctx, x_lims);
        
        mask_vis = (common_space >= x_lims(1)) & (common_space <= x_lims(2));
        all_y = [];
        if show_front
            y_temp = filt_F(mask_vis);
            all_y = [all_y; y_temp(:)];
        end
        if show_rear
            y_temp = filt_R(mask_vis);
            all_y = [all_y; y_temp(:)];
        end
        
        if ~isempty(all_y)
            y_max = max(all_y); y_min = min(all_y); range_y = y_max - y_min; 
            if range_y < 1e-6, range_y = 1; end 
            ylim(ax_ctx, [y_min - 0.2*range_y, y_max + 0.3*range_y]);
        end

        try draw_infra_overlay(ax_ctx, h.InfraMap, x_lims); catch, end
        try draw_joints_overlay(ax_ctx, h.JointsMap, x_lims); catch ME, disp(['Errore Giunti Contesto: ' ME.message]); end

        title(ax_ctx, ['FILT FULL (Ricalcolato): ' fName], 'Interpreter', 'none', 'FontSize', 8, 'FontWeight', 'bold');
        legend(ax_ctx, 'show', 'Location', 'northeast');
        ax_ctx.XAxis.Exponent = 0;
        
        % =========================================================
        % PLOT 2: RMS (Sui dati FILTRATI)
        % =========================================================
        hold(ax_rms, 'on'); grid(ax_rms, 'on');
        
       if show_front
            area(ax_rms, common_space, rms_F, 'FaceColor', [0.6 0.7 1], ...
                 'EdgeColor', 'none', 'FaceAlpha', 0.6, 'DisplayName', 'RMS Front (Filt)');
            plot(ax_rms, common_space, th_F, 'Color', [0 0.4 0.8], ...
                 'LineWidth', 1.5, 'DisplayName', 'Threshold Front (x3)');
        end
        if show_rear
            area(ax_rms, common_space, rms_R, 'FaceColor', [1 0.7 0.7], ...
                 'EdgeColor', 'none', 'FaceAlpha', 0.6, 'DisplayName', 'RMS Rear (Filt)');
            plot(ax_rms, common_space, th_R, 'Color', [0.8 0 0], ...
                 'LineWidth', 1.5, 'DisplayName', 'Threshold Rear (x3)');
        end

        yline(ax_rms, C.ABS_RMS_THRESH, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Soglia Ass. (%.1f)', C.ABS_RMS_THRESH));
        xline(ax_rms, center_pk, 'k--', 'LineWidth', 1.5);
        
        xlim(ax_rms, [center_pk - 200, center_pk + 200]);
        ax_rms.XAxis.Exponent = 0; 
        
        mask_z = (common_space >= center_pk-200 & common_space <= center_pk+200);
        env_vis = [];
        if show_front, env_vis = [env_vis; rms_F(mask_z)]; end
        if show_rear,  env_vis = [env_vis; rms_R(mask_z)]; end
        mx_v = max(env_vis(:)); if isempty(mx_v) || mx_v==0, mx_v=10; end
        ylim(ax_rms, [0, min(mx_v, 50)*1.2]);
        
        title(ax_rms, 'Analisi RMS (Filtrata)');
        legend(ax_rms, 'show', 'Location', 'northeast');
        
    catch ME
        cla(ax_ctx); 
        text(ax_ctx, 0.5, 0.5, ['Error: ' ME.message], 'HorizontalAlignment', 'center', 'Interpreter', 'none', 'Color', 'r');
    end
end


function shifted_sig = helper_fft_shift(sig, shift_m, spatial_res)
    % Questa funzione replica esattamente shift_signal_frac del DB Creator
    N = length(sig);
    if N <= 1, shifted_sig = sig; return; end
    
    % Vettore colonna per sicurezza
    sig_work = double(sig(:));
    shift_samples = shift_m / spatial_res;
    
    X = fft(sig_work);
    k = (0:N-1)';
    k(k > floor(N/2)) = k(k > floor(N/2)) - N; 
    
    phase_shift = exp(-1i * 2 * pi * k * shift_samples / N);
    shifted_sig = real(ifft(X .* phase_shift));
    
    % Riporta alla forma originale (riga/colonna)
    if isrow(sig), shifted_sig = shifted_sig'; end
end


function cla_all(h), cla(h.AxTrend); cla(h.AxContext); cla(h.AxCfar); arrayfun(@cla, h.Axes); end

function draw_infra_overlay(ax, infra_table, x_limits)
    if isempty(infra_table), return; end
    vis_idx = (infra_table.Pk_Inizio <= x_limits(2)) & (infra_table.Pk_Fine >= x_limits(1)); visible_items = infra_table(vis_idx, :); if isempty(visible_items), return; end
    y_lims = get(ax, 'YLim'); hold(ax, 'on');
    for i = 1:height(visible_items)
        row = visible_items(i, :); x_start = row.Pk_Inizio; x_end = row.Pk_Fine;
        if strcmpi(row.Tipo, 'Deviatoio'), col = [1 0.7 0.7]; txt_col = [0.8 0 0]; else, col = [0.7 1 0.7]; txt_col = [0 0.5 0]; end
        patch(ax, [x_start x_end x_end x_start], [y_lims(1) y_lims(1) y_lims(2) y_lims(2)], col, 'EdgeColor', 'none', 'FaceAlpha', 0.3);
        if (x_end - x_start) > (x_limits(2) - x_limits(1)) * 0.02
             lbl = row.Descrizione; if strlength(lbl) > 15, lbl = extractBefore(lbl, 15) + ".."; end
             text(ax, x_start, y_lims(2), lbl, 'Color', txt_col, 'VerticalAlignment', 'top', 'FontSize', 7, 'Interpreter', 'none');
        end
    end
end



% function draw_joints_overlay(ax, joints_table, x_limits)
%     if isempty(joints_table), return; end
% 
%     % Assumiamo che Position sia la colonna 2 e il Nome del Giunto sia la colonna 3
%     posizioni = joints_table{:, 2}; 
%     nomi = joints_table{:, 3};      
% 
%     % Trova i giunti che cadono dentro la finestra del grafico attuale
%     vis_idx = (posizioni >= x_limits(1)) & (posizioni <= x_limits(2));
% 
%     pos_visibili = posizioni(vis_idx);
%     nomi_visibili = nomi(vis_idx);
% 
%     if isempty(pos_visibili), return; end
% 
%     hold(ax, 'on');
%     for i = 1:length(pos_visibili)
%         pos = pos_visibili(i);
%         nome_giunto = string(nomi_visibili(i));
% 
%         % Disegna una linea verticale magenta continua e un po' più spessa
%         xline(ax, pos, 'm-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
% 
%         % Testo col nome del giunto
%         y_lims = get(ax, 'YLim');
%         text(ax, pos, y_lims(1) + (y_lims(2)-y_lims(1))*0.05, char(nome_giunto), ...
%             'Color', 'm', 'Rotation', 90, 'FontSize', 8, 'Interpreter', 'none', 'FontWeight', 'bold');
%     end
% end


function draw_joints_overlay(ax, joints_table, x_limits)
    if isempty(joints_table), return; end
    
    % Position = colonna 2, Nome giunto = colonna 3
    posizioni = joints_table{:, 2}; 
    nomi      = joints_table{:, 3};      
    
    % Disegna TUTTI i giunti del foglio, svincolato da x_limits:
    % le linee restano presenti quando si fa pan/zoom orizzontale.
    hold(ax, 'on');
    y_lims = get(ax, 'YLim');
    for i = 1:numel(posizioni)
        pos = posizioni(i);
        if isnan(pos), continue; end
        nome_giunto = string(nomi(i));
        
        xline(ax, pos, 'm-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
        text(ax, pos, y_lims(1) + (y_lims(2)-y_lims(1))*0.05, char(nome_giunto), ...
            'Color', 'm', 'Rotation', 90, 'FontSize', 8, 'Interpreter', 'none', 'FontWeight', 'bold');
    end
end
function dati_binario = load_infrastructure_map(filename, track_type)
    if strcmpi(track_type, 'pari'), sheets = {'1 p', '1 dp'}; else, sheets = {'1 d', '1 dd'}; end
    dati_binario = table(); if ~exist(filename, 'file'), return; end
    for s = 1:length(sheets)
        sheetName = sheets{s}; try raw_data = readcell(filename, 'Sheet', sheetName); catch, continue; end
        [num_rows, ~] = size(raw_data); idx_descA = 1; idx_descM = 13; idx_L_Dev = 12; idx_L1 = 16; idx_L2 = 18; idx_Pk_Start = 20; idx_Pk_End = 21;
        for i = 3:num_rows
            row = raw_data(i, :); if size(row, 2) < idx_Pk_End, continue; end
            pk_start = helper_clean_val(row, idx_Pk_Start); pk_end = helper_clean_val(row, idx_Pk_End); if pk_start == 0 && pk_end == 0, continue; end
            desc_A = string(row{idx_descA}); if ismissing(desc_A), desc_A=""; end
            desc_M = string(row{idx_descM}); if ismissing(desc_M), desc_M=""; end
            if contains(desc_A, 'Dev', 'IgnoreCase', true) || contains(desc_M, 'Dev', 'IgnoreCase', true)
                newRow = table({sheetName}, "Deviatoio", pk_start, pk_end, desc_A + " " + desc_M, 'VariableNames', {'Foglio', 'Tipo', 'Pk_Inizio', 'Pk_Fine', 'Descrizione'}); dati_binario = [dati_binario; newRow];
            end
            if contains(desc_M, 'Destra', 'IgnoreCase', true) || contains(desc_M, 'Sinistra', 'IgnoreCase', true)
                l1 = helper_clean_val(row, idx_L1); if l1==0 && i>1, l1=helper_clean_val(raw_data(i-1,:), idx_L1); end
                if l1>0, newRow=table({sheetName}, "Raccordo Ingresso", pk_start, pk_start+l1, "Racc. Ing "+desc_M, 'VariableNames', {'Foglio', 'Tipo', 'Pk_Inizio', 'Pk_Fine', 'Descrizione'}); dati_binario=[dati_binario; newRow]; end
                l2 = helper_clean_val(row, idx_L2); if l2==0 && i<num_rows, l2=helper_clean_val(raw_data(i+1,:), idx_L2); end
                if l2>0, newRow=table({sheetName}, "Raccordo Uscita", pk_end-l2, pk_end, "Racc. Usc "+desc_M, 'VariableNames', {'Foglio', 'Tipo', 'Pk_Inizio', 'Pk_Fine', 'Descrizione'}); dati_binario=[dati_binario; newRow]; end
            end
        end
    end
end
function val = helper_clean_val(row, idx)
    if idx > length(row), val = 0; return; end
    val = row{idx}; if ismissing(val) || ischar(val) || isstring(val), val = 0; end
    if ~isnumeric(val), val = 0; end
end

% =========================================================================
% FUNZIONE HELPER: TOOLTIP
% =========================================================================
function txt = custom_datatip(~, event_obj, pk_list)
    target = event_obj.Target;
    pos = event_obj.Position;
    
    if ~isprop(target, 'Tag') || ~strcmp(target.Tag, 'DefectScatter')
        txt = {['X: ', num2str(pos(1), '%.2f')], ['Y: ', num2str(pos(2), '%.2f')]};
        return;
    end
    
    idx = event_obj.DataIndex;
    if idx <= length(pk_list), pk_str = pk_list{idx}; else, pk_str = 'N/A'; end
    txt = {pk_str, ['Ant: ', num2str(pos(1), '%.2f')], ['Pos: ', num2str(pos(2), '%.2f')]};
end
% =========================================================================
% CALLBACK: ANALISI APPROFONDITA (8 SENSORI + STATISTICHE + STFT)
% =========================================================================
function on_open_single_analysis(src, ~)
    h = guidata(src);
    if isempty(h.DB) || isempty(h.CurrDefectIdx), msgbox('Seleziona un difetto.'); return; end
    Defect = h.DB(h.CurrDefectIdx);
    if isfield(h,'DateFrom') && ~isempty(h.DateFrom)
        Defect = filter_defect_by_dates(Defect, h.DateFrom, h.DateTo);
    end
    History = Defect.History;
    
    n_runs = length(History);

    PSD_Mode = '2D'; 
    ax_psd = gobjects(1);

    if n_runs < 3
        warndlg('Servono almeno 3 passaggi storici per un''analisi sensata.', 'Dati Insufficienti');
        return;
    end
    
    if n_runs < 3
        warndlg('Servono almeno 3 passaggi storici per un''analisi sensata.', 'Dati Insufficienti');
        return;
    end
    
    % --- INIT VARIABILI AE (Tab 8) ---
    % Devono esistere prima di recalc_metrics() -> update_IPI_Score(),
    % anche se la Tab 8 viene costruita più avanti (linea ~2746).
    AE_Net    = [];
    AE_mu     = [];
    AE_sigma  = [];
    AE_v_ref  = [];
    AE_Results = struct('DateNum', {}, 'MSE', {}, 'Original', {}, 'Reconstructed', {});
    % --- DEFINIZIONE LISTE SENSORI (8 CANALI) ---
    % Ordine: [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]
    sensor_fields_list = {
        'left_sensor_front',      'left_sensor_rear', ...
        'right_sensor_front',     'right_sensor_rear', ...
        'right_sensor_front_lat', 'right_sensor_rear_lat', ...
        'left_sensor_front_lat',  'left_sensor_rear_lat'
    };
    
    % Nomi per menu a tendina
    sensor_titles_dropdown = {
        'Vert SX (Front)', 'Vert SX (Rear)', ...
        'Vert DX (Front)', 'Vert DX (Rear)', ...
        'Lat DX (Front)',  'Lat DX (Rear)', ...
        'Lat SX (Front)',  'Lat SX (Rear)'
    };
    
    % Titoli per i 4 grafici di Trend (Coppie)
    plot_titles = {
        'Verticale SX [m/s^2]', 'Verticale DX [m/s^2]', ...
        'Laterale DX [m/s^2]',  'Laterale SX [m/s^2]'
        };
    pairs_idx = [1, 2; 3, 4; 5, 6; 7, 8]; 
    
    % --- 1. ESTRAZIONE DATI PER TUTTI GLI 8 SENSORI ---
    AllAmps = nan(n_runs, 8); 
    dates_num = zeros(n_runs, 1); 
    %RawDataStore(n_runs) = struct('Date', [], 'Signals', [], 'Axis', [], 'Amp', []); 
    %dx_default = 0.01; 
    PSD_Mode = '2D';
    WINDOW_SIZE = h.CFG.WINDOW_SIZE;
    dx_default  = h.CFG.SPATIAL_RES;
    RawDataStore(n_runs) = struct('Date', [], 'Signals', [], 'Axis', [], 'Amp', [], 'Speed', []);
    wb = waitbar(0, 'Estrazione Dati Completi (8 Canali)...');
    
    for i = 1:n_runs
        if mod(i, 20) == 0, waitbar(i/n_runs, wb); end
        run = History(i);
        dates_num(i) = datenum(run.Date);
        
        RawDataStore(i).Date = run.Date;
        RawDataStore(i).Amp  = run.Amp;

        if isfield(run.Data, 'Speed')
            RawDataStore(i).Speed = run.Data.Speed;
        else
            RawDataStore(i).Speed = NaN;
        end
        if isfield(run, 'Detected')
            RawDataStore(i).Detected = run.Detected;
        else
            RawDataStore(i).Detected = true;
        end

        RawDataStore(i).Signals = struct();


        % --- Calcolo dei campioni per la finestra RMS ---
        % Usiamo la WINDOW_SIZE definita in h.CFG (es. 5m) 
        % win_samples_base = max(3, round(WINDOW_SIZE / dx_default));
% prova con window di 0.5m
        win_samples_base = max(3, round(0.5 / dx_default));
        if isfield(run.Data, 'Filt')
            for s = 1:8
                sn = sensor_fields_list{s};
                if isfield(run.Data.Filt, sn)
                    sig = run.Data.Filt.(sn);
                    
                    % --- NUOVA LOGICA: Max RMS invece di Picco Assoluto ---
                    if length(sig) >= win_samples_base
                        % Calcola il profilo RMS su tutto il segnale
                        rms_sig = sqrt(movmean(sig.^2, win_samples_base));
                        % Estrae l'energia massima dell'urto
                        val_max_rms = max(rms_sig);
                    else
                        % Fallback di sicurezza se il segnale è anomalo o troppo corto
                        val_max_rms = max(abs(sig));
                    end
                    
                    AllAmps(i, s) = val_max_rms;
                    RawDataStore(i).Signals.(sn) = sig(:);
                else
                    AllAmps(i, s) = 0; 
                end
            end
            
            if isfield(run.Data, 'RelativeAxis')
                ax_loc = run.Data.RelativeAxis(:);
            elseif isfield(run.Data.Filt, sensor_fields_list{1})
                L = length(run.Data.Filt.(sensor_fields_list{1})); 
                ax_loc = linspace(-L/2*dx_default, L/2*dx_default, L)';
            else
                ax_loc = []; 
            end
            RawDataStore(i).Axis = ax_loc;
        end
    end
    waitbar(1, wb, 'Rendering...'); close(wb);
    
    [dates_num, sort_idx] = sort(dates_num);
    AllAmps = AllAmps(sort_idx, :);
    RawDataStore = RawDataStore(sort_idx);
    

    % --- INIZIO NUOVI CALCOLI PER TAB EVOLUTIVE ---
    Ratio_SX_DX = zeros(n_runs, 1);
    Ratio_FR    = zeros(n_runs, 1);
    Ratio_LV    = zeros(n_runs, 1);
    Lambda_All  = zeros(n_runs, 8);
    Severity    = zeros(n_runs, 1);
    
    fs_space = 1 / dx_default;
    NFFT_val = max(4, round(10.0 / dx_default)); % Finestra 10m per Lambda
    
    for i = 1:n_runs
        % Estrazione dalle ampiezze già calcolate in AllAmps
        % Ordine: [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]
        A_SX_F = AllAmps(i, 1); A_SX_R = AllAmps(i, 2);
        A_DX_F = AllAmps(i, 3); A_DX_R = AllAmps(i, 4);
        A_LAT_MAX = max(AllAmps(i, 5:8));
        
        A_VERT_MAX = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
        Severity(i) = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
        
        % denom_dx   = max(A_DX_F + A_DX_R, 1e-6);
        % denom_rear = max(A_SX_R + A_DX_R, 1e-6);
        
        Ratio_SX_DX(i) = (A_SX_F + A_SX_R) / max(A_DX_F + A_DX_R,1e-6);
        Ratio_FR(i)    = (A_SX_F + A_DX_F) / max(A_SX_R + A_DX_R,1e-6);
        Ratio_LV(i)    = A_LAT_MAX / max(A_VERT_MAX, 1e-6);

       % --- Calcolo Lambda veloce per TUTTI i sensori ---
        for s = 1:8
            sn = sensor_fields_list{s};
            if isfield(RawDataStore(i).Signals, sn)
                sig_tmp = double(RawDataStore(i).Signals.(sn));
                Lambda_All(i, s) = get_quick_lambda_local(sig_tmp, NFFT_val, fs_space);
            end
        end
    end
    % --- FINE NUOVI CALCOLI ---


    days_floor = floor(dates_num);
    unique_days = unique(days_floor);
    n_days = length(unique_days);

    % --- SETUP FIGURA ---
    % --- SETUP FIGURA ---
    f_stat = figure('Name', ['Analisi Approfondita: ' Defect.ID_PK], 'Color', 'w', 'WindowState', 'maximized');

    % 1. CREA IL PULSANTE DI ESPORTAZIONE IN ALTO A DESTRA
    btn_export_report = uicontrol('Parent', f_stat, 'Style', 'pushbutton', ...
        'String', '💾 ESPORTA REPORT PICCO', ...
        'Units', 'normalized', 'Position', [0.82 0.95 0.17 0.04], ...
        'BackgroundColor', [0.8 1 0.8], 'FontWeight', 'bold', ...
        'Callback', @export_peak_report);

    % 2. CREA IL TABGROUP ABASSANDOLO LEGGERMENTE PER FARE SPAZIO AL PULSANTE
    tabgp = uitabgroup(f_stat, 'Units', 'normalized', 'Position', [0 0 1 0.94]);

    % =====================================================================
    % TAB 1: TREND TEMPORALE (4 GRAFICI)
    % =====================================================================
    tab1 = uitab(tabgp, 'Title', 'Trend Temporale');
    ax_list = gobjects(4,1); 
    margins = [0.06, 0.06]; h_gap = 0.10; h_plot = (0.86 - 3*h_gap) / 4;
    
    for p = 1:4
        bot_pos = 0.05 + (4-p)*(h_plot + h_gap);
        ax_list(p) = axes('Parent', tab1, 'Position', [margins(1), bot_pos, 1-sum(margins), h_plot]);
        hold(ax_list(p), 'on'); grid(ax_list(p), 'on');
        
        idx_F = pairs_idx(p, 1); idx_R = pairs_idx(p, 2);
        mean_F = zeros(n_days,1); mean_R = zeros(n_days,1);
        
        for k = 1:n_days
            mask = (days_floor == unique_days(k));
            vals_F = AllAmps(mask, idx_F); if isempty(vals_F), mean_F(k)=0; else, mean_F(k)=mean(vals_F); end
            vals_R = AllAmps(mask, idx_R); if isempty(vals_R), mean_R(k)=0; else, mean_R(k)=mean(vals_R); end
        end
        
        plot(ax_list(p), unique_days, mean_F, 'b-o', 'MarkerFaceColor', 'b', 'MarkerSize', 4, 'DisplayName', 'Front');
        plot(ax_list(p), unique_days, mean_R, 'r-s', 'MarkerFaceColor', 'r', 'MarkerSize', 4, 'DisplayName', 'Rear');
        title(ax_list(p), {plot_titles{p}; 'Media giornaliera dei valori di MAX(RMS), finestra 0.5m  '}, 'FontSize', 9, 'FontWeight', 'bold');
        ylabel(ax_list(p), 'Accelerazione [m/s^2]', 'FontSize', 8); 
        if p==4, datetick(ax_list(p), 'x', 'dd/mm/yy', 'keeplimits', 'keepticks'); else, set(ax_list(p), 'XTickLabel', []); end
        if p==1, legend(ax_list(p), 'Location', 'northwest', 'Orientation', 'horizontal'); end
    end
    linkaxes(ax_list, 'x');
    
    % --- NUOVO: Attiva il tooltip con le date ---
    dcm_stat = datacursormode(f_stat);
    set(dcm_stat, 'UpdateFcn', @master_datatip_fcn);
    
    % =====================================================================
    % TAB 2: ANALISI PROFILO & STATISTICHE
    % =====================================================================
    tab_ctrl = uitab(tabgp, 'Title', 'Statistiche & Profilo');
    pnl_ctrl = uipanel('Parent', tab_ctrl, 'Position', [0.01 0.88 0.98 0.11], 'BackgroundColor', 'w', 'BorderType', 'none');
    
    uicontrol('Parent', pnl_ctrl, 'Style', 'text', 'String', 'Gruppo:', 'Units', 'normalized', 'Position', [0.01 0.3 0.06 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    stat_groups_dropdown = {'Verticale SX (Media F+R)', 'Verticale DX (Media F+R)', 'Laterale DX (Media F+R)', 'Laterale SX (Media F+R)'};
    pop_sensor = uicontrol('Parent', pnl_ctrl, 'Style', 'popupmenu', 'String', stat_groups_dropdown, 'Units', 'normalized', 'Position', [0.08 0.3 0.17 0.4], 'Callback', @on_ctrl_change, 'Value', 1);

    uicontrol('Parent', pnl_ctrl, 'Style', 'text', 'String', 'Win [m]:', 'Units', 'normalized', 'Position', [0.25 0.3 0.05 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    lbl_win = uicontrol('Parent', pnl_ctrl, 'Style', 'text', 'String', '0.50 m', 'Units', 'normalized', 'Position', [0.31 0.3 0.05 0.4], 'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold');
    sld_win = uicontrol('Parent', pnl_ctrl, 'Style', 'slider', 'Min', 0.1, 'Max', 3.0, 'Value', 0.5, 'Units', 'normalized', 'Position', [0.37 0.3 0.15 0.4], 'Callback', @on_ctrl_change);
    
    uicontrol('Parent', pnl_ctrl, 'Style', 'text', 'String', 'Grafico:', 'Units', 'normalized', 'Position', [0.54 0.3 0.05 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    pop_graph = uicontrol('Parent', pnl_ctrl, 'Style', 'popupmenu', 'String', {'Energia (RMS)', 'Simmetria (Skew)', 'Kurtosis', 'Crest Factor'}, 'Units', 'normalized', 'Position', [0.60 0.3 0.16 0.4], 'Callback', @on_graph_change);

    % --- NUOVO CONTROLLO: MEDIA settimanale o giornaliera---
    uicontrol('Parent', pnl_ctrl, 'Style', 'text', 'String', 'Media:', 'Units', 'normalized', 'Position', [0.77 0.3 0.05 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    %pop_grouping = uicontrol('Parent', pnl_ctrl, 'Style', 'popupmenu', 'String', {'Giornaliera', 'Settimanale', 'Mensile'}, 'Units', 'normalized', 'Position', [0.83 0.3 0.15 0.4], 'Callback', @on_ctrl_change, 'Value', 1);
    pop_grouping = uicontrol('Parent', pnl_ctrl, 'Style', 'popupmenu', 'String', {'Singole Corse', 'Giornaliera', 'Settimanale', 'Mensile'}, 'Units', 'normalized', 'Position', [0.83 0.3 0.15 0.4], 'Callback', @on_ctrl_change, 'Value', 1);
    
      % --- AGGIORNATA CON COLONNE 3x3 E LAMBDA ---
    col_names = {'Data', 'Velocità [km/h]', 'Picco [m/s^2]', 'Max RMS', 'Skew', 'Kurt', 'Crest', 'Pos 3x3 [lat-long]', 'Lambda [m]'};
    t_table = uitable('Parent', tab_ctrl, 'Data', {}, 'ColumnName', col_names, ...
        'Units', 'normalized', 'Position', [0.01 0.02 0.40 0.84], 'RowName', [], ...
        'ColumnWidth', {70, 110, 55, 60, 40, 40, 40, 55, 65});
    ax3 = axes('Parent', tab_ctrl, 'Position', [0.46 0.08 0.52 0.78]);
    grid(ax3, 'on'); hold(ax3, 'on'); title(ax3, 'Evoluzione Profilo', 'FontSize', 11, 'FontWeight', 'bold');
    
    Cache_Profiles = struct('RMS', {}, 'Skew', {}, 'Kurt', {}, 'Crest', {}, 'Axis', {});
    
        % --- CALCOLO METRICHE (CORRETTO PER DATETIME) ---
    function recalc_metrics()
        win_m = get(sld_win, 'Value');
        win_samples = round(win_m / dx_default); if win_samples < 3, win_samples=3; end

        stat_pairs = {
            'left_sensor_front',      'left_sensor_rear';
            'right_sensor_front',     'right_sensor_rear';
            'right_sensor_front_lat', 'right_sensor_rear_lat';
            'left_sensor_front_lat',  'left_sensor_rear_lat'
            };
        sens_idx = get(pop_sensor, 'Value');
        sel_sens_front = stat_pairs{sens_idx, 1};
        sel_sens_rear  = stat_pairs{sens_idx, 2};

        all_dates = [RawDataStore.Date];
        if isempty(all_dates)
            set(t_table, 'Data', {}); cla(ax3); return;
        end

        % Convertiamo tutto in datetime in modo robusto
        if ~isdatetime(all_dates)
            all_dates_dt = datetime(all_dates, 'ConvertFrom', 'datenum');
        else
            all_dates_dt = all_dates;
        end

        % --- NUOVA LOGICA DI RAGGRUPPAMENTO IN RECALC_METRICS ---
        grouping_val = get(pop_grouping, 'Value');

        switch grouping_val
            case 1
                dates_rounded = all_dates_dt;
                str_waitbar = 'Elaborazione Singole Corse...';
            case 2
                dates_rounded = dateshift(all_dates_dt, 'start', 'day');
                str_waitbar = 'Calcolo Media Giornaliera...';
            case 3
                dates_rounded = dateshift(all_dates_dt - days(1), 'start', 'week') + days(1);
                str_waitbar = 'Calcolo Media Settimanale...';
            case 4
                dates_rounded = dateshift(all_dates_dt, 'start', 'month');
                str_waitbar = 'Calcolo Media Mensile...';
        end

        [unique_periods, ~, ic] = unique(dates_rounded);
        n_periods = length(unique_periods);

        % Preallocazione
        Cache_Profiles = struct('RMS', cell(n_periods,1), 'Skew', cell(n_periods,1), ...
            'Kurt', cell(n_periods,1), 'Crest', cell(n_periods,1), ...
            'Axis', cell(n_periods,1), 'Date', cell(n_periods,1));

        table_data = cell(n_periods, 9);

        common_axis = -WINDOW_SIZE : dx_default : WINDOW_SIZE;

        wb_calc = waitbar(0, str_waitbar);

        for k = 1:n_periods
            waitbar(k/n_periods, wb_calc);
            day_idxs = find(ic == k);
            
            sigs_matrix = [];
            max_amp_day = 0;
            speeds_day = [];
            
            for j = 1:length(day_idxs)
                run_idx = day_idxs(j);
                
                v_run = RawDataStore(run_idx).Speed;
                if ~isnan(v_run) && v_run > 0
                    speeds_day(end+1) = v_run;
                end
                
                % Lista dei due sensori (Front e Rear) da sovrapporre/mediare
                sensors_to_check = {sel_sens_front, sel_sens_rear};
                for s = 1:2
                    sens_name = sensors_to_check{s};
                    if isfield(RawDataStore(run_idx).Signals, sens_name)
                        sig = double(RawDataStore(run_idx).Signals.(sens_name));
                        ax_loc = RawDataStore(run_idx).Axis;
                        
                        % --- IL VERO PICCO ASSOLUTO ---
                        if ~isempty(sig)
                            max_amp_day = max(max_amp_day, max(abs(sig)));
                        end
                        
                        % --- INTERPOLAZIONE E ACCUMULO ---
                        if ~isempty(sig) && ~isempty(ax_loc) && length(sig) > 1 && length(ax_loc) > 1
                            L_min = min(length(sig), length(ax_loc));
                            sig_final = sig(1:L_min);
                            ax_final  = double(ax_loc(1:L_min));
                            if length(ax_final) >= 2
                                sig_interp = interp1(ax_final, sig_final, common_axis, 'linear', 0);
                                sigs_matrix = [sigs_matrix; sig_interp];
                            end
                        end
                    end
                end
            end
            
            if ~isempty(sigs_matrix)
                n_sigs = size(sigs_matrix, 1);
                n_samples = size(sigs_matrix, 2);
                
                % --- NUOVA LOGICA: PREALLOCAZIONE PER I SINGOLI SEGNALI ---
                all_rms_profiles   = zeros(n_sigs, n_samples);
                all_skew_profiles  = zeros(n_sigs, n_samples);
                all_kurt_profiles  = zeros(n_sigs, n_samples);
                all_crest_profiles = zeros(n_sigs, n_samples);
                all_max_rms        = zeros(n_sigs, 1);
                
                % --- CALCOLO METRICHE SU OGNI SINGOLO SEGNALE ---
                for row_idx = 1:n_sigs
                    sig_row = sigs_matrix(row_idx, :)';
                    
                    % 1. Calcolo RMS e Max RMS per questa singola corsa
                    rms_row = sqrt(movmean(sig_row.^2, win_samples));
                    all_rms_profiles(row_idx, :) = rms_row';
                    all_max_rms(row_idx) = max(rms_row);
                    
                    % 2. Calcolo altre statistiche sul singolo segnale
                    all_skew_profiles(row_idx, :)  = moving_window_stat(sig_row, win_samples, @skewness)';
                    all_kurt_profiles(row_idx, :)  = moving_window_stat(sig_row, win_samples, @kurtosis)';
                    all_crest_profiles(row_idx, :) = (movmax(abs(sig_row), win_samples) ./ (rms_row + eps))';
                end
                
                % --- MEDIA DEI RISULTATI ---
                % Profilo medio per tracciare il grafico Waterfall 3D
                p_rms   = mean(all_rms_profiles, 1, 'omitnan')';
                p_skew  = mean(all_skew_profiles, 1, 'omitnan')';
                p_kurt  = mean(all_kurt_profiles, 1, 'omitnan')';
                p_crest = mean(all_crest_profiles, 1, 'omitnan')';
                
                Cache_Profiles(k).RMS   = p_rms;
                Cache_Profiles(k).Skew  = p_skew;
                Cache_Profiles(k).Kurt  = p_kurt;
                Cache_Profiles(k).Crest = p_crest;
                Cache_Profiles(k).Axis  = common_axis;
                Cache_Profiles(k).Date  = unique_periods(k); % Salviamo il datetime
                
                % --- IL VALORE PER LA TABELLA: Media dei Max RMS singoli ---
                mean_of_max_rms = mean(all_max_rms, 'omitnan');
                
                % Troviamo l'indice del picco sul profilo RMS medio per estrarre le statistiche puntuali
                [~, idx_pk] = max(p_rms);
                
                % Formattazione orario se Singola Corsa
                if grouping_val == 1
                    d_str = datestr(unique_periods(k), 'dd/mm/yy HH:MM');
                else
                    d_str = datestr(unique_periods(k), 'dd/mm/yy');
                end
                
                % --- FORMATTAZIONE STRINGA VELOCITÀ ---
                if isempty(speeds_day)
                    speed_str = 'N/A';
                else
                    mean_v = mean(speeds_day);
                    indiv_v_str = sprintf('%d, ', round(speeds_day));
                    indiv_v_str = indiv_v_str(1:end-2); % Rimuove l'ultima virgola
                    if length(speeds_day) == 1
                        speed_str = sprintf('%.1f', mean_v);
                    else
                        speed_str = sprintf('%.1f [%s]', mean_v, indiv_v_str);
                    end
                end
                
                % =========================================================
                % --- NUOVO: CALCOLO POSIZIONE MATRICE 3X3 ---
                % =========================================================
                mean_ratio_X = mean(Ratio_SX_DX(day_idxs), 'omitnan');
                mean_ratio_Y = mean(Ratio_FR(day_idxs), 'omitnan');
                
                % Classificazione Laterale (Left, Center, Right)
                if isnan(mean_ratio_X), lat_char = '-';
                elseif mean_ratio_X > 2.0, lat_char = 'L';
                elseif mean_ratio_X < 0.5, lat_char = 'R';
                else, lat_char = 'C'; end
                
                % Classificazione Longitudinale (Front, Center, Rear)
                if isnan(mean_ratio_Y), long_char = '-';
                elseif mean_ratio_Y > 2.0, long_char = 'F';
                elseif mean_ratio_Y < 0.5, long_char = 'R';
                else, long_char = 'C'; end
                
                pos_3x3_str = sprintf('%s-%s', lat_char, long_char);

                % =========================================================
                % --- NUOVO: CALCOLO LAMBDA MEDIO PER I SENSORI SELEZIONATI
                % =========================================================
                idx_sens_f = find(strcmp(sensor_fields_list, sel_sens_front));
                idx_sens_r = find(strcmp(sensor_fields_list, sel_sens_rear));
                
                lams_f = Lambda_All(day_idxs, idx_sens_f);
                lams_r = Lambda_All(day_idxs, idx_sens_r);
                
                valid_lams = [lams_f(:); lams_r(:)];
                valid_lams = valid_lams(valid_lams > 0); 
                
                if isempty(valid_lams)
                    mean_lambda = 0; 
                else
                    mean_lambda = round(mean(valid_lams), 2);
                end
                
                % --- INSERIMENTO DATI NELLA TABELLA (9 colonne) ---
                table_data(k, :) = {d_str, speed_str, max_amp_day, mean_of_max_rms, ...
                                    p_skew(idx_pk), p_kurt(idx_pk), p_crest(idx_pk), ...
                                    pos_3x3_str, mean_lambda};
            else
                d_str = datestr(unique_periods(k), 'dd/mm/yy');
                % --- FALLBACK SE NON CI SONO DATI VALIDI (9 colonne) ---
                table_data(k, :) = {d_str, 'N/A', 0, 0, 0, 0, 0, '-', 0};
            end
        end
        close(wb_calc);
        set(t_table, 'Data', table_data);
        update_dynamic_plot();
        update_IPI_Score();
    end

    % --- GRAFICO DINAMICO 3D (WATERFALL) ---
    function update_dynamic_plot()
        cla(ax3); 
        
        % 1. FILTRO SALVAVITA: Ignora i giorni in cui il sensore era spento/assente
        valid_mask = ~cellfun(@isempty, {Cache_Profiles.Date});
        Valid_Profiles = Cache_Profiles(valid_mask);
        
        n_periods = length(Valid_Profiles); 
        if n_periods == 0
            title(ax3, 'Nessun dato disponibile (Sensore spento o assente)', 'FontSize', 11);
            return; 
        end
        
        type_idx = get(pop_graph, 'Value'); 
        
        % 2. Preparazione delle Matrici per il 3D solo sui dati validi
        X = Valid_Profiles(1).Axis;
        Y = zeros(n_periods, 1);
        Z = zeros(n_periods, length(X));
        
        for k = 1:n_periods
            % Popoliamo l'asse Y con le date (convertite in formato numerico per il plot)
            if isdatetime(Valid_Profiles(k).Date)
                Y(k) = datenum(Valid_Profiles(k).Date);
            else
                Y(k) = Valid_Profiles(k).Date;
            end
            
            % Popoliamo la matrice Z con la metrica selezionata
            switch type_idx
                case 1, Z(k,:) = Valid_Profiles(k).RMS;
                case 2, Z(k,:) = Valid_Profiles(k).Skew;
                case 3, Z(k,:) = Valid_Profiles(k).Kurt;
                case 4, Z(k,:) = Valid_Profiles(k).Crest;
            end
        end
        
        % 3. Creazione del Grafico 3D (Waterfall)
        % waterfall disegna linee solide lungo X, separate lungo Y
        h_wf = waterfall(ax3, X, Y, Z);
        
        % Estetica: linee morbide e leggermente trasparenti
        set(h_wf, 'LineWidth', 1.5, 'FaceAlpha', 0.8, 'EdgeColor', 'interp');
        
        % 4. Impostazione della Vista e degli Assi
        view(ax3, -37.5, 30); % Vista 3D (tre quarti)
        grid(ax3, 'on');
        
        % Asse Y: Mostriamo le date invece dei numeri grezzi
        datetick(ax3, 'y', 'mmm yy', 'keeplimits', 'keepticks');
        
        % 5. Colori
        colormap(ax3, jet); 
        colorbar(ax3); % Ora la colorbar indica il valore di Z (Severità)
        
        % 6. Etichette e Titoli
        xlabel(ax3, 'Posizione [m]', 'FontWeight', 'bold');
        ylabel(ax3, 'Tempo', 'FontWeight', 'bold');
        
        switch type_idx
            case 1, zlabel(ax3, 'RMS Medio [m/s^2]', 'FontWeight', 'bold');
            case 2, zlabel(ax3, 'Skewness', 'FontWeight', 'bold');
            case 3, zlabel(ax3, 'Kurtosis', 'FontWeight', 'bold');
            case 4, zlabel(ax3, 'Crest Factor', 'FontWeight', 'bold');
        end

        % Titolo dinamico in base al raggruppamento (mostra il numero di giorni validi)
        grouping_val = get(pop_grouping, 'Value');
        % NUOVO (CORRETTO)
        switch grouping_val
            case 1
                title(ax3, sprintf('Evoluzione 3D (Singole Corse) - %d Corse valide', n_periods), 'FontSize', 11);
            case 2
                title(ax3, sprintf('Evoluzione 3D (Giornaliera) - %d Giorni validi', n_periods), 'FontSize', 11);
            case 3
                title(ax3, sprintf('Evoluzione 3D (Settimanale) - %d Settimane valide', n_periods), 'FontSize', 11);
            case 4
                title(ax3, sprintf('Evoluzione 3D (Mensile) - %d Mesi validi', n_periods), 'FontSize', 11);
        end
    end

    % Funzione helper per statistiche mobili
    function out = moving_window_stat(sig, k, fun_handle)
        n = length(sig); 
        out = zeros(n, 1);
        step = 1; if n > 2000, step = 5; end % Ottimizzazione per segnali lunghi
        
        half_k = floor(k/2);
        
        for ii = 1:step:n
            i_start = max(1, ii - half_k);
            i_end   = min(n, ii + half_k);
            chunk = sig(i_start:i_end);
            if ~isempty(chunk)
                out(ii) = fun_handle(chunk);
            end
        end
        
        % Interpolazione se abbiamo saltato step
        if step > 1
            idx_filled = 1:step:n;
            out = interp1(idx_filled, out(idx_filled), 1:n, 'linear', 'extrap')';
        end
    end
    recalc_metrics();

% =====================================================================
    % TAB 3: SPETTROGRAMMA
    % =====================================================================
    tab_stft = uitab(tabgp, 'Title', 'Spettrogramma');
    pnl_stft_ctrl = uipanel('Parent', tab_stft, 'Position', [0.01 0.88 0.98 0.11], 'BackgroundColor', 'w');
    
    stft_list_display = [{'--- OVERVIEW (8 Canali) ---'}, sensor_titles_dropdown]; 
    
    % --- CONTROLLI ESISTENTI ---
    uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', 'Vista:', 'Units', 'normalized', 'Position', [0.01 0.3 0.04 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    pop_stft_sens = uicontrol('Parent', pnl_stft_ctrl, 'Style', 'popupmenu', 'String', stft_list_display, 'Units', 'normalized', 'Position', [0.05 0.3 0.15 0.4], 'Callback', @update_stft, 'Value', 1); 
    
    
    uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', 'Run:', 'Units', 'normalized', 'Position', [0.21 0.3 0.04 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    
    stft_dates = cell(length(RawDataStore), 1);
    for k = 1:length(RawDataStore)
        stft_dates{k} = sprintf('%s  [ %.1f m/s^2 ]', datestr(RawDataStore(k).Date, 'dd/mm/yy HH:MM'), RawDataStore(k).Amp);
    end
    
    % --- MODIFICA: Menu ristretto per fare spazio ---
    pop_stft_run = uicontrol('Parent', pnl_stft_ctrl, 'Style', 'popupmenu', 'String', stft_dates, ...
        'Units', 'normalized', 'Position', [0.26 0.3 0.14 0.4], 'Callback', @update_stft, 'Value', length(RawDataStore));
    
    % --- NUOVO: Pulsante Run Critica ---
    uicontrol('Parent', pnl_stft_ctrl, 'Style', 'pushbutton', 'String', '🔥 MAX', ...
        'Units', 'normalized', 'Position', [0.405 0.3 0.04 0.4], ...
        'BackgroundColor', [1 0.6 0.2], 'FontWeight', 'bold', ...
        'TooltipString', 'Vai direttamente alla run con accelerazione massima', ...
        'Callback', @goto_max_run);
    
    % uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', 'Win [m]:', 'Units', 'normalized', 'Position', [0.45 0.3 0.06 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');


    uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', 'Win [m]:', 'Units', 'normalized', 'Position', [0.45 0.3 0.06 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    edit_win_size = uicontrol('Parent', pnl_stft_ctrl, 'Style', 'edit', 'String', '1.0', 'Units', 'normalized', 'Position', [0.52 0.3 0.04 0.4], 'Callback', @update_stft);
    
    % --- CURSORE RANGE DINAMICO (dB) ---
    uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', 'Range:', 'Units', 'normalized', 'Position', [0.58 0.3 0.05 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    lbl_db = uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', '40 dB', 'Units', 'normalized', 'Position', [0.64 0.3 0.05 0.4], 'BackgroundColor', [0.9 0.9 0.9], 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    sld_db = uicontrol('Parent', pnl_stft_ctrl, 'Style', 'slider', 'Min', 10, 'Max', 80, 'Value', 40, 'Units', 'normalized', 'Position', [0.70 0.3 0.15 0.4], 'Callback', @update_stft);
    
    % --- NUOVO: NOTA INFORMATIVA SUI SETTING ---
    info_str = 'Note STFT: Finestra Hamming, 90% overlap. Overview (8 canali) usa scala colori globale prendendo il max di tutti 8 come rosso scuro. Zoom Singolo usa scala adattiva.';
    uicontrol('Parent', pnl_stft_ctrl, 'Style', 'text', 'String', info_str, 'Units', 'normalized', ...
        'Position', [0.01 0.01 0.98 0.25], 'BackgroundColor', [1 0.98 0.8], 'ForegroundColor', [0.4 0.3 0], ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'FontAngle', 'italic');

    pnl_stft_plot = uipanel('Parent', tab_stft, 'Position', [0.01 0.01 0.98 0.86], 'BackgroundColor', 'w', 'BorderType', 'none');
    update_stft(); % Inizializza subito lo spettrogramma
    


    % =====================================================================
    % TAB 4: POWER SPECTRAL DENSITY (PSD)
    % =====================================================================
    tab_psd = uitab(tabgp, 'Title', 'Analisi PSD');
    pnl_psd_ctrl = uipanel('Parent', tab_psd, 'Position', [0.01 0.88 0.98 0.11], 'BackgroundColor', 'w');
    
    % --- CONTROLLI ---
    uicontrol('Parent', pnl_psd_ctrl, 'Style', 'text', 'String', 'Sensore:', 'Units', 'normalized', 'Position', [0.01 0.3 0.05 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    pop_psd_sens = uicontrol('Parent', pnl_psd_ctrl, 'Style', 'popupmenu', 'String', sensor_titles_dropdown, 'Units', 'normalized', 'Position', [0.06 0.3 0.14 0.4], 'Callback', @refresh_psd_view, 'Value', 1);
    
    uicontrol('Parent', pnl_psd_ctrl, 'Style', 'text', 'String', 'Run:', 'Units', 'normalized', 'Position', [0.21 0.3 0.03 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    pop_psd_run = uicontrol('Parent', pnl_psd_ctrl, 'Style', 'popupmenu', 'String', stft_dates, 'Units', 'normalized', 'Position', [0.25 0.3 0.16 0.4], 'Callback', @refresh_psd_view, 'Value', length(RawDataStore));
    
    uicontrol('Parent', pnl_psd_ctrl, 'Style', 'text', 'String', 'Win [m]:', 'Units', 'normalized', 'Position', [0.42 0.3 0.04 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    % edit_psd_win = uicontrol('Parent', pnl_psd_ctrl, 'Style', 'edit', 'String', '2.0', 'Units', 'normalized', 'Position', [0.47 0.3 0.03 0.4], 'Callback', @refresh_psd_view);
    edit_psd_win = uicontrol('Parent', pnl_psd_ctrl, 'Style', 'edit', 'String', '10.0', 'Units', 'normalized', 'Position', [0.47 0.3 0.03 0.4], 'Callback', @refresh_psd_view);
    % controlli pds
    %uicontrol('Parent', pnl_psd_ctrl, 'Style', 'text', 'String', 'Overlap:', 'Units', 'normalized', 'Position', [0.50 0.3 0.04 0.4], 'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    %pop_psd_overlap = uicontrol('Parent', pnl_psd_ctrl, 'Style', 'popupmenu', 'String', {'25%', '50%', '75%', '90%'}, 'Units', 'normalized', 'Position', [0.55 0.3 0.05 0.4], 'Callback', @refresh_psd_view, 'Value', 2);
    % pop_psd_overlap = uicontrol('Parent', pnl_psd_ctrl, 'Style', 'popupmenu', 'String', {'0%', '25%', '50%', '75%', '90%'}, 'Units', 'normalized', 'Position', [0.55 0.3 0.05 0.4], 'Callback', @refresh_psd_view, 'Value', 3);
    uicontrol('Parent', pnl_psd_ctrl, 'Style', 'pushbutton', 'String', 'Vista 2D', ...
    'Units', 'normalized', 'Position', [0.61 0.3 0.07 0.4], 'Callback', @(~,~) switch_psd_mode('2D'));
    
    uicontrol('Parent', pnl_psd_ctrl, 'Style', 'pushbutton', 'String', 'Vista 3D Evolutiva', ...
    'Units', 'normalized', 'Position', [0.69 0.3 0.10 0.4], 'BackgroundColor', [0.8 1 0.8], ...
    'FontWeight', 'bold', 'Callback', @(~,~) switch_psd_mode('3D'));
    % Note Sintetiche
    uicontrol('Parent', pnl_psd_ctrl, 'Style', 'text', 'String', sprintf('PSD centrata sul picco (es. Win=2m -> +- 1m).\nFinestra Hamming, no Zero-Padding.\nMedie psd3D: Si media il profilo, non i segnali grezzi.\n medie scelte nella tab 2 es settimanale/ mensile'), 'Units', 'normalized', 'Position', [0.8 0.1 0.28 0.8], 'BackgroundColor', [1 1 0.9], 'FontSize', 8, 'HorizontalAlignment', 'left', 'FontAngle', 'italic');

    pnl_psd_plot = uipanel('Parent', tab_psd, 'Position', [0.01 0.01 0.98 0.86], 'BackgroundColor', 'w', 'BorderType', 'none');
    ax_psd = axes('Parent', pnl_psd_plot, 'Position', [0.10 0.15 0.85 0.70]); 
    grid(ax_psd, 'on'); hold(ax_psd, 'on');



  % =====================================================================
    % NUOVA TAB 5: MATRICE 3x3 (TRAIETTORIA CINEMATICA)
    % =====================================================================
    tab_3x3 = uitab(tabgp, 'Title', 'Matrice 3x3 Evolutiva');
    ax_3x3 = axes('Parent', tab_3x3, 'Position', [0.1 0.1 0.75 0.7]);


    % --- NOTA INFORMATIVA MATRICE 3X3 (Migliorata visivamente) ---
    nota_3x3 = sprintf('Mappa la simmetria dell''urto sui 4 angoli del carrello.\nBasata sui rapporti delle energie (Max RMS, finestra fissa 0.5m).\nAttivando i raggruppamenti (es. mensile), i rapporti vengono mediati.');
    
    uicontrol('Parent', tab_3x3, 'Style', 'text', 'String', nota_3x3, ...
        'Units', 'normalized', ...
        'Position', [0.03 0.9 0.5 0.1], ... % <--- Più largo (0.35) e più basso (0.08)
        'BackgroundColor', [0.98 0.98 0.96], ... % Giallo molto più tenue e professionale
        'ForegroundColor', [0.3 0.3 0.3], ... % Testo grigio scuro, meno aggressivo del nero
        'FontSize', 9, 'HorizontalAlignment', 'left', 'FontAngle', 'italic');
    % SALVIAMO I GRAFICI NELLE VARIABILI h_line_3x3 E h_scat_3x3
    h_line_3x3 = plot(ax_3x3, Ratio_SX_DX, Ratio_FR, '-', 'Color', [0.8 0.8 0.8], 'LineWidth', 1.5, 'HandleVisibility', 'off');
    h_scat_3x3 = scatter(ax_3x3, Ratio_SX_DX, Ratio_FR, 60, dates_num, 'filled', 'MarkerEdgeColor', 'k');
    
    xline(ax_3x3, 2.0, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Left');
    xline(ax_3x3, 0.5, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Right');
    yline(ax_3x3, 2.0, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Front');
    yline(ax_3x3, 0.5, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Rear');
    
    set(ax_3x3, 'XScale', 'log', 'YScale', 'log');
    xlabel(ax_3x3, 'Ratio Laterale (SX / DX)', 'FontWeight', 'bold');
    ylabel(ax_3x3, 'Ratio Longitudinale (Front / Rear)', 'FontWeight', 'bold');
    title(ax_3x3, 'Rapporti FRONT-REAR e LEFT-RIGHT (Colore = Evoluzione Temporale)', 'FontWeight', 'bold');
    
    colormap(ax_3x3, parula); cb = colorbar(ax_3x3);
    datetick(cb, 'y', 'mm/yy'); ylabel(cb, 'Evoluzione Temporale', 'FontWeight', 'bold');
    
    % Salviamo anche il testo per poterlo spostare
    h_text_3x3 = text(ax_3x3, Ratio_SX_DX(end), Ratio_FR(end), '  ← ATTUALE', 'Color', 'r', 'FontWeight', 'bold');

    % =====================================================================
    % NUOVA TAB 6: RATIO LATERALE VS TEMPO
    % =====================================================================
    tab_lat = uitab(tabgp, 'Title', 'Rapporti laterale verticale');
    ax_lat = axes('Parent', tab_lat, 'Position', [0.1 0.15 0.8 0.75]);
    hold(ax_lat, 'on'); grid(ax_lat, 'on');
    
    h_plot_lat = plot(ax_lat, dates_num, Ratio_LV, '-ok', 'LineWidth', 2, 'MarkerFaceColor', 'y', 'MarkerSize', 6);
    yline(ax_lat, 0.6, 'r-', 'LineWidth', 2, 'DisplayName', 'Soglia Critica Laterale (0.6)');
    
    datetick(ax_lat, 'x', 'dd/mm/yy', 'keepticks', 'keeplimits');
    xlabel(ax_lat, 'Data', 'FontWeight', 'bold'); ylabel(ax_lat, 'Ratio Laterale / Verticale', 'FontWeight', 'bold');
    title(ax_lat, 'Evoluzione della Componente Laterale nel Tempo', 'FontWeight', 'bold');

    % =====================================================================
    % NUOVA TAB 7: EVOLUZIONE LUNGHEZZA D'ONDA (LAMBDA)
    % =====================================================================
    tab_lam = uitab(tabgp, 'Title', 'Evoluzione Lambda');
    % Riduco la larghezza dell'asse a 0.7 per fare spazio alla legenda fuori
    ax_lam = axes('Parent', tab_lam, 'Position', [0.1 0.15 0.7 0.75]); 
    hold(ax_lam, 'on'); grid(ax_lam, 'on');
    
    % Generazione automatica delle linee per tutti i sensori
    colors = lines(8); % Tavolozza di 8 colori distinti
    h_plot_lam = gobjects(8, 1);
    
    for s = 1:8
        h_plot_lam(s) = plot(ax_lam, dates_num, Lambda_All(:, s), '-o', ...
            'LineWidth', 1.5, 'MarkerSize', 5, ...
            'Color', colors(s,:), 'MarkerFaceColor', colors(s,:), ...
            'DisplayName', sensor_titles_dropdown{s});
    end
    
    datetick(ax_lam, 'x', 'dd/mm/yy', 'keepticks', 'keeplimits');
    xlabel(ax_lam, 'Data', 'FontWeight', 'bold'); 
    ylabel(ax_lam, 'Lunghezza d''onda \lambda [m]', 'FontWeight', 'bold');
    title(ax_lam, 'Evoluzione Lunghezza d''onda (Tutti i Sensori)', 'FontWeight', 'bold');
    
    % Legenda esterna
    legend(ax_lam, 'Location', 'eastoutside');
    
    % Zoom dinamico intelligente basato sui dati reali
    axis(ax_lam, 'tight');
    ylims = ylim(ax_lam);
    ylim(ax_lam, [0, max(0.5, ylims(2) * 1.1)]); % Margine del 10% sopra il valore max
    


% =====================================================================
    % NUOVA TAB: EVOLUZIONE PCA (ANALISI C - AUTOENCODER LINEARE)
    % =====================================================================
    tab_pca = uitab(tabgp, 'Title', 'Evoluzione PCA');

    % Header con indici riassuntivi (entrambe le direzioni)
    pnl_pca_hdr = uipanel('Parent', tab_pca, 'Position', [0.01 0.94 0.98 0.05], ...
        'BackgroundColor', 'w', 'BorderType', 'line');
    lbl_pca_hdr = uicontrol('Parent', pnl_pca_hdr, 'Style', 'text', ...
        'String', 'Calcolo PCA in corso...', 'Units', 'normalized', ...
        'Position', [0.01 0.05 0.98 0.9], 'BackgroundColor', 'w', ...
        'FontWeight', 'bold', 'FontSize', 10, 'HorizontalAlignment', 'center');

    % Pannello controlli (dropdown direzione)
    pnl_pca_ctrl = uipanel('Parent', tab_pca, 'Position', [0.01 0.88 0.98 0.05], ...
        'BackgroundColor', 'w', 'BorderType', 'none');
    uicontrol('Parent', pnl_pca_ctrl, 'Style', 'text', 'String', 'Direzione:', ...
        'Units', 'normalized', 'Position', [0.40 0.2 0.06 0.6], ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    pop_pca_dir = uicontrol('Parent', pnl_pca_ctrl, 'Style', 'popupmenu', ...
        'String', {'Forward', 'Backward'}, 'Units', 'normalized', ...
        'Position', [0.47 0.2 0.10 0.6], 'Value', 1, 'Callback', @on_pca_dir_change);

    % Slider per esplorare k
    uicontrol('Parent', pnl_pca_ctrl, 'Style', 'text', 'String', 'k:', ...
        'Units', 'normalized', 'Position', [0.62 0.2 0.02 0.6], ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    sld_k = uicontrol('Parent', pnl_pca_ctrl, 'Style', 'slider', ...
        'Min', 1, 'Max', 6, 'Value', 2, 'SliderStep', [1/45 5/45], ...
        'Units', 'normalized', 'Position', [0.65 0.3 0.20 0.4], ...
        'Callback', @on_k_slider_change);
    lbl_k_val = uicontrol('Parent', pnl_pca_ctrl, 'Style', 'text', ...
        'String', 'k = 2 (preset)', 'Units', 'normalized', ...
        'Position', [0.86 0.2 0.07 0.6], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', ...
        'ForegroundColor', [0.6 0 0]);
    btn_k_reset = uicontrol('Parent', pnl_pca_ctrl, 'Style', 'pushbutton', ...
        'String', 'Preset (k=2)', 'Units', 'normalized', ...
        'Position', [0.93 0.3 0.06 0.4], 'Callback', @on_k_reset);


    % Selettore vista manifold (3D / proiezione PC1 / proiezione PC2)
    uicontrol('Parent', pnl_pca_ctrl, 'Style', 'text', 'String', 'Vista:', ...
        'Units', 'normalized', 'Position', [0.02 0.2 0.05 0.6], ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    pop_pca_view = uicontrol('Parent', pnl_pca_ctrl, 'Style', 'popupmenu', ...
        'String', {'3D', 'PC1 vs Tempo', 'PC2 vs Tempo'}, 'Units', 'normalized', ...
        'Position', [0.08 0.2 0.13 0.6], 'Value', 1, 'Callback', @on_pca_view_change);

    % ---- NUOVO: bottone clustering manifold ----
    uicontrol('Parent', pnl_pca_ctrl, 'Style', 'pushbutton', ...
        'String', '🔵 Clustering Passaggi', 'Units', 'normalized', ...
        'Position', [0.23 0.15 0.15 0.70], ...
        'BackgroundColor', [0.18 0.39 0.68], 'ForegroundColor', 'w', ...
        'FontWeight', 'bold', 'FontSize', 9, ...
        'TooltipString', 'Apre K-Means clustering sul manifold PCA (direzione corrente)', ...
        'Callback', @on_open_pca_clustering);

    % Assi: scree | anomaly score vs tempo | manifold | confronto firma
    % Ho ridotto l'altezza a 0.30 e posizionato la base a 0.55
    ax_pca_scree = axes('Parent', tab_pca, 'Position', [0.06 0.55 0.40 0.30]);
    ax_pca_anom  = axes('Parent', tab_pca, 'Position', [0.55 0.55 0.42 0.30]);
    
    % I grafici inferiori partono più in basso (0.05) e si fermano a 0.44 (0.05+0.39)
    % Questo crea un "gap" verticale di 0.11 per far respirare titoli ed etichette
    ax_pca_mani  = axes('Parent', tab_pca, 'Position', [0.06 0.05 0.40 0.39]);
    
    % Firma: pannello con griglia 2x3 (un sottografico per sensore)
    pnl_pca_sig = uipanel('Parent', tab_pca, 'Position', [0.55 0.05 0.42 0.39], ...
        'BackgroundColor', 'w', 'BorderType', 'none');
        
    lbl_pca_sig_title = uicontrol('Parent', pnl_pca_sig, 'Style', 'text', ...
        'Units', 'normalized', 'Position', [0.0 0.92 1.0 0.08], 'String', '', ...
        'BackgroundColor', 'w', 'FontWeight', 'bold', 'FontSize', 9, ...
        'HorizontalAlignment', 'center');
        
    ax_pca_sig = gobjects(1, 6);
    
    % Spaziature interne ricalibrate per il nuovo pannello per evitare schiacciamenti
    sig_mx = 0.09; sig_my = 0.12; sig_gx = 0.07; sig_gy = 0.18; sig_top = 0.85;
    
    sig_aw = (1 - 2*sig_mx - 2*sig_gx) / 3;
    sig_ah = (sig_top - sig_my - sig_gy) / 2;
    
    for cc = 1:6
        rr = floor((cc-1)/3);                  % 0 = riga alta, 1 = riga bassa
        kk = mod(cc-1, 3);                     % 0..2 colonna
        ax_x = sig_mx + kk*(sig_aw + sig_gx);
        ax_y = sig_top - sig_ah - rr*(sig_ah + sig_gy);
        ax_pca_sig(cc) = axes('Parent', pnl_pca_sig, 'Position', [ax_x ax_y sig_aw sig_ah]);
    end
    % Storage modelli (calcolati una volta, switchati via dropdown)
    PCA_Models = struct('Forward', [], 'Backward', []);


    % Calcolo entrambi i modelli (smistamento + PCA + visualizzazione)
       run_pca_full_pipeline();
  % ---------------------------------------------------------------------
    function run_pca_full_pipeline()
        MIN_RUNS = 30;
        N_GRID   = 333;
        x_grid   = linspace(-h.CFG.WINDOW_SIZE, h.CFG.WINDOW_SIZE, N_GRID);
        win_m    = 0.5;
        n_chan   = 6;

        % Etichette per i 6 canali (significato fisico, non nome del field)
        ch_labels = {'V SX-F','V DX-F','Lat-F','V SX-R','V DX-R','Lat-R'};

        % --- 1. Smista i passaggi per orientation ---
        idx_fwd = false(n_runs, 1);
        idx_bwd = false(n_runs, 1);
        n_unassigned = 0;
        for i = 1:n_runs
            run_i = History(i);
            d     = run_i.Data;
            if ~isfield(d, 'Filt'), n_unassigned = n_unassigned + 1; continue; end
            Fd = d.Filt;

            ori = '';
            if isfield(run_i, 'orientation') && ~isempty(run_i.orientation)
                ori = lower(strtrim(char(run_i.orientation)));
            elseif isfield(d, 'orientation') && ~isempty(d.orientation)
                ori = lower(strtrim(char(d.orientation)));
            end

            if contains(ori, 'forward')
                idx_fwd(i) = true;
            elseif contains(ori, 'backward')
                idx_bwd(i) = true;
            else
                % Fallback: confronto RMS dei laterali front
                rms_right = 0; rms_left = 0;
                if isfield(Fd, 'right_sensor_front_lat') && ~isempty(Fd.right_sensor_front_lat)
                    s = double(Fd.right_sensor_front_lat);
                    s = s(isfinite(s));
                    if ~isempty(s), rms_right = sqrt(mean(s.^2)); end
                end
                if isfield(Fd, 'left_sensor_front_lat') && ~isempty(Fd.left_sensor_front_lat)
                    s = double(Fd.left_sensor_front_lat);
                    s = s(isfinite(s));
                    if ~isempty(s), rms_left = sqrt(mean(s.^2)); end
                end
                if rms_right > rms_left
                    idx_fwd(i) = true;
                elseif rms_left > rms_right
                    idx_bwd(i) = true;
                else
                    n_unassigned = n_unassigned + 1;
                end
            end
        end
        fprintf('[PCA] Smistamento: forward=%d, backward=%d, non-assegnati=%d (totale %d)\n', ...
                sum(idx_fwd), sum(idx_bwd), n_unassigned, n_runs);

        % --- 2. Calcola modello per ciascuna direzione ---
        fprintf('[PCA] Inizio Forward...\n');
        PCA_Models.Forward  = build_pca_model(find(idx_fwd),  'Forward', ...
                                              x_grid, win_m, n_chan, MIN_RUNS, ch_labels);
        fprintf('[PCA] Forward completato. Inizio Backward...\n');
        PCA_Models.Backward = build_pca_model(find(idx_bwd), 'Backward', ...
                                              x_grid, win_m, n_chan, MIN_RUNS, ch_labels);
        fprintf('[PCA] Backward completato.\n');

        % --- 3. Header riassuntivo ---
        hdr_str = format_pca_header(PCA_Models);
        set(lbl_pca_hdr, 'String', hdr_str, 'ForegroundColor', [0 0.3 0]);

        % --- 4. Visualizza la prima direzione disponibile ---
        if ~isempty(PCA_Models.Forward)
            set(pop_pca_dir, 'Value', 1);
            display_pca_model(PCA_Models.Forward);
        elseif ~isempty(PCA_Models.Backward)
            set(pop_pca_dir, 'Value', 2);
            display_pca_model(PCA_Models.Backward);
        else
            set(lbl_pca_hdr, 'String', ...
                sprintf('Passaggi insufficienti in entrambe le direzioni (servono %d per dir).', MIN_RUNS), ...
                'ForegroundColor', [0.7 0 0]);
        end
    end
    % ---------------------------------------------------------------------
    function M = build_pca_model(run_idx, label, x_grid, win_m, n_chan, MIN_RUNS, ch_labels)
        M = [];
        fprintf('[PCA %s] Entrato in build_pca_model con %d passaggi\n', label, numel(run_idx));
        n_sel = numel(run_idx);
        if n_sel < MIN_RUNS
            fprintf('[PCA %s] Solo %d passaggi (serve %d). Skip.\n', label, n_sel, MIN_RUNS);
            return;
        end

        N_GRID      = length(x_grid);
        win_samples = max(3, round(win_m / h.CFG.SPATIAL_RES));

        X        = nan(n_sel, n_chan * N_GRID);
        dates_v  = nan(n_sel, 1);
        amps_v   = nan(n_sel, 1);
        valid_v  = false(n_sel, 1);
        fail_reason = zeros(n_sel, 1);   % 0=ok, 1=noFilt, 2=noAxis, 3=missingChan, 4=lenMismatch, 5=interpNaN

        wb_msg = sprintf('PCA %s: estrazione feature...', label);
        wb     = waitbar(0, wb_msg, 'Name', 'Calcolo PCA');

        switch lower(label)
            case 'forward'
                lat_F_field = 'right_sensor_front_lat';
                lat_R_field = 'right_sensor_rear_lat';
            case 'backward'
                lat_F_field = 'left_sensor_front_lat';
                lat_R_field = 'left_sensor_rear_lat';
        end

        chan_fields = {'left_sensor_front', 'right_sensor_front', lat_F_field, ...
                       'left_sensor_rear', 'right_sensor_rear', lat_R_field};

        for k = 1:n_sel
            if mod(k, 10) == 0
                waitbar(k/n_sel, wb, sprintf('%s: passaggio %d/%d', wb_msg, k, n_sel));
            end

            i = run_idx(k);
            run_i = History(i);
            dates_v(k) = datenum(run_i.Date);
            amps_v(k)  = run_i.Amp;
            d = run_i.Data;

            if ~isfield(d, 'Filt'), fail_reason(k) = 1; continue; end
            Fd = d.Filt;

            if ~isfield(d, 'RelativeAxis') || isempty(d.RelativeAxis)
                fail_reason(k) = 2; continue;
            end
            ax_src = double(d.RelativeAxis(:));
            if ~issorted(ax_src) || any(~isfinite(ax_src))
                fail_reason(k) = 2; continue;
            end

            row    = nan(1, n_chan * N_GRID);
            row_ok = true;
            for c = 1:n_chan
                fn = chan_fields{c};
                if ~isfield(Fd, fn) || isempty(Fd.(fn))
                    row_ok = false; fail_reason(k) = 3; break;
                end
                sig = double(Fd.(fn)(:));
                if length(sig) ~= length(ax_src) || numel(sig) < 10
                    row_ok = false; fail_reason(k) = 4; break;
                end
                env = sqrt(movmean(sig.^2, win_samples));
                env_g = interp1(ax_src, env, x_grid, 'linear', NaN);
                if any(~isfinite(env_g))
                    row_ok = false; fail_reason(k) = 5; break;
                end
                row((c-1)*N_GRID + 1 : c*N_GRID) = env_g;
            end

            if row_ok
                X(k, :) = row;
                valid_v(k) = true;
            end
        end

        % Report fallimenti
        n_fail = sum(~valid_v);
        if n_fail > 0
            counts = histcounts(fail_reason(~valid_v), 0.5:1:5.5);
            fprintf(['[PCA %s] Falliti %d/%d - noFilt:%d noAxis:%d missingChan:%d ', ...
                     'lenMismatch:%d interpNaN:%d\n'], label, n_fail, n_sel, ...
                    counts(1), counts(2), counts(3), counts(4), counts(5));
        end

        X       = X(valid_v, :);
        dates_v = dates_v(valid_v);
        amps_v  = amps_v(valid_v);
        n_valid = size(X, 1);
        if n_valid < MIN_RUNS
            close(wb);
            fprintf('[PCA %s] Solo %d passaggi validi dopo estrazione. Skip.\n', label, n_valid);
            return;
        end

       % ============================================================
        % ANALISI PARALLELA (channel-space PCA)
        % Le 6 tracce sono spazialmente allineate: a ogni posizione i 6
        % canali sono osservazioni simultanee dello stesso evento.
        %   osservazioni = (passaggio x posizione), variabili = 6 canali
        %   PC1 = modo comune (tutti si muovono insieme)
        %   residuo = quanto un canale rompe il pattern condiviso
        % ============================================================
        waitbar(1, wb, sprintf('PCA %s: riarrangiamento parallelo...', label));

        Xraw   = X;                      % n_valid x (n_chan*N_GRID), inviluppi NON standardizzati
        Nrows  = n_valid * N_GRID;
        Xpar   = zeros(Nrows, n_chan);   % (passaggio x posizione) x canale
        run_id = zeros(Nrows, 1);
        for r = 1:n_valid
            base = (r-1)*N_GRID;
            run_id(base+1 : base+N_GRID) = r;
            for c = 1:n_chan
                cols = (c-1)*N_GRID + 1 : c*N_GRID;
                Xpar(base+1 : base+N_GRID, c) = Xraw(r, cols).';
            end
        end

        % Standardizzazione per-canale (sulle colonne: stessa scala per ogni sensore)
        mu_ch = mean(Xpar, 1);
        sg_ch = std(Xpar, 0, 1);
        sg_ch(sg_ch < 1e-9) = 1;
        Xpar_z = (Xpar - mu_ch) ./ sg_ch;

        % PCA nello spazio dei canali (6 variabili)
        waitbar(1, wb, sprintf('PCA %s: calcolo componenti...', label));
        try
            [coeffs, scores, ~, ~, explained, mu_pca] = pca(Xpar_z, 'Economy', true);
        catch ME
            close(wb);
            fprintf('[PCA %s] Errore in pca(): %s\n', label, ME.message);
            return;
        end

        cumvar = cumsum(explained);
        k = min(2, size(coeffs, 2));

        % Residuo per riga (passaggio x posizione) -> RMSE aggregato per passaggio
        resid_z  = scores(:, k+1:end) * coeffs(:, k+1:end)';   % Nrows x n_chan
        se_row   = mean(resid_z.^2, 2);
        rmse_run = sqrt(accumarray(run_id, se_row, [n_valid 1], @mean));

        % Score per passaggio (media sulle posizioni) per il manifold
        P = size(scores, 2);
        scores_run = zeros(n_valid, P);
        for j = 1:P
            scores_run(:, j) = accumarray(run_id, scores(:, j), [n_valid 1], @mean);
        end

        % Ricostruzione destandardizzata, rimessa in layout 6*N (per la firma)
        recon_chan       = (scores(:, 1:k) * coeffs(:, 1:k)' + mu_pca) .* sg_ch + mu_ch;  % Nrows x n_chan
        X_recon_unscaled = zeros(n_valid, n_chan * N_GRID);
        for r = 1:n_valid
            base = (r-1)*N_GRID;
            for c = 1:n_chan
                cols = (c-1)*N_GRID + 1 : c*N_GRID;
                X_recon_unscaled(r, cols) = recon_chan(base+1 : base+N_GRID, c).';
            end
        end
        X_orig_unscaled = Xraw;

        % Ordinamento cronologico
        [dates_sorted, ord] = sort(dates_v);
        rmse_sorted   = rmse_run(ord);
        scores_sorted = scores_run(ord, :);
        X_orig_sorted = X_orig_unscaled(ord, :);
        X_recon_sorted = X_recon_unscaled(ord, :);

        % Ampiezza + canale del picco (per datatip), in ordine cronologico
        N = N_GRID;
        amps_vec      = nan(n_valid, 1);
        peak_chan_idx = nan(n_valid, 1);
        for kk = 1:n_valid
            ch_peaks = nan(1, n_chan);
            for c = 1:n_chan
                cols = (c-1)*N + 1 : c*N;
                ch_peaks(c) = max(X_orig_sorted(kk, cols));
            end
            [amps_vec(kk), peak_chan_idx(kk)] = max(ch_peaks);
        end

        M = struct();
        M.label      = label;
        M.n_valid    = n_valid;
        M.k          = k;
        M.mu_ch      = mu_ch;            % 1 x n_chan
        M.sg_ch      = sg_ch;            % 1 x n_chan
        M.mu_pca     = mu_pca;           % 1 x n_chan
        M.var_k      = cumvar(k);
        M.coeffs     = coeffs;           % n_chan x P
        M.scores     = scores_sorted;    % per-passaggio (manifold), ordinato
        M.explained  = explained;
        M.dates      = dates_sorted;
        M.amps          = amps_vec;
        M.peak_chan_idx = peak_chan_idx;
        M.rmse       = rmse_sorted;
        M.rmse_mean  = mean(rmse_sorted);
        M.X_orig     = X_orig_sorted;    % n_valid x (n_chan*N)
        M.X_recon    = X_recon_sorted;   % fallback
        M.x_grid     = x_grid;
        M.n_chan     = n_chan;
        M.ch_labels  = ch_labels;
        M.N_GRID     = N_GRID;
        % campi per ricalcolo a k variabile (slider / firma)
        M.scores_full = scores;          % (passaggio x posizione) x P, ordine ORIGINALE
        M.run_id      = run_id;          % indice passaggio (ordine originale)
        M.ord_run     = ord;             % sorted -> originale: run_orig = ord(idx_sorted)

        fprintf('[PCA %s] OK (parallelo): %d passaggi, k=%d, var=%.1f%%, RMSE medio=%.3f\n', ...
                label, n_valid, k, M.var_k, M.rmse_mean);
        close(wb);
    
    end



% ---------------------------------------------------------------------
    function on_k_slider_change(src, ~)
        k_new = round(get(src, 'Value'));
        set(src, 'Value', k_new);   % snap a intero
        v = get(pop_pca_dir, 'Value');
        if v == 1
            M = PCA_Models.Forward;
        else
            M = PCA_Models.Backward;
        end
        if isempty(M), return; end
        update_with_new_k(M, k_new);
    end

    % ---------------------------------------------------------------------
    function on_k_reset(~, ~)
        v = get(pop_pca_dir, 'Value');
        if v == 1
            M = PCA_Models.Forward;
        else
            M = PCA_Models.Backward;
        end
        if isempty(M), return; end
        max_k_avail = get(sld_k, 'Max');
        k_auto = min(M.k, max_k_avail);
        set(sld_k, 'Value', k_auto);
        update_with_new_k(M, M.k);
    end

    % ---------------------------------------------------------------------
    function update_with_new_k(M, k_new)
        % Indica nel label se k è auto o manuale
        if k_new == M.k
            set(lbl_k_val, 'String', sprintf('k = %d (auto)', k_new), ...
                           'ForegroundColor', [0.6 0 0]);
        else
            set(lbl_k_val, 'String', sprintf('k = %d (manuale)', k_new), ...
                           'ForegroundColor', [0 0.4 0]);
        end

        % Ricalcola ricostruzione e RMSE con il nuovo k
        N      = M.N_GRID;
        n_chan = M.n_chan;

        %% Ricalcolo RMSE per-passaggio nello spazio dei canali (analisi parallela)
        resid_z   = M.scores_full(:, k_new+1:end) * M.coeffs(:, k_new+1:end)';
        se_row    = mean(resid_z.^2, 2);
        rmse_orig = sqrt(accumarray(M.run_id, se_row, [M.n_valid 1], @mean));
        rmse_new  = rmse_orig(M.ord_run);   % riporta in ordine cronologico
        
        % Aggiorna pannello Anomaly Score
        cla(ax_pca_anom, 'reset'); hold(ax_pca_anom, 'on');
        legend(ax_pca_anom, 'off');
        try
            for ax = [ax_pca_anom, ax_pca_sig]
                delete(findall(ax, 'Type', 'datatip'));
            end
        catch
        end

        %datatip anomaly  score
        h_anom_pts = scatter(ax_pca_anom, M.dates, rmse_new, 35, M.amps, 'filled', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.3, ...
                'ButtonDownFcn', @(s,e) on_pca_point_click_dynamic(M, rmse_new));
        h_anom_pts.DataTipTemplate.DataTipRows = [
            dataTipTextRow('Data', datetime(M.dates, 'ConvertFrom', 'datenum'), 'dd/MM/yy')
            dataTipTextRow('RMSE (k)',   rmse_new,          '%.4f')
            dataTipTextRow('Peak RMS',   M.amps,            '%.2f m/s²')
            dataTipTextRow('Canale peak', M.ch_labels(M.peak_chan_idx)')
        ];


        rmse_mean_new = mean(rmse_new);
        thr           = rmse_mean_new + 2*std(rmse_new);

        % Trend lineare
        t_norm = M.dates - M.dates(1);
        p_fit  = polyfit(t_norm, rmse_new, 1);
        h_trend = plot(ax_pca_anom, M.dates, polyval(p_fit, t_norm), ...
                       'r-', 'LineWidth', 2);

        % Media mobile
        n_pts = length(M.dates);
        w_win = max(3, round(n_pts/15));
        h_mov = plot(ax_pca_anom, M.dates, movmean(rmse_new, w_win), ...
                     'k-', 'LineWidth', 1.5);

        h_thr = yline(ax_pca_anom, thr, '--r', '\mu + 2\sigma', 'LineWidth', 1.2);
        h_mu  = yline(ax_pca_anom, rmse_mean_new, ':k', '\mu', 'LineWidth', 1);
        datetick(ax_pca_anom, 'x', 'dd/mm/yy', 'keeplimits');
        xlabel(ax_pca_anom, 'Data'); ylabel(ax_pca_anom, 'RMSE ricostruzione');
        slope_per_day = p_fit(1);
        title(ax_pca_anom, sprintf('Anomaly Score (k=%d, \\mu=%.3f, trend=%+.5f/giorno) - %s', ...
            k_new, rmse_mean_new, slope_per_day, M.label));
        grid(ax_pca_anom, 'on');
        cb = colorbar(ax_pca_anom);
        cb.Label.String = 'Max RMS 0.5m tra i sensori [m/s^2]';
        cb.Label.Interpreter = 'tex';
        legend([h_trend, h_mov], {'Trend lineare', sprintf('Media mobile w=%d', w_win)}, ...
            'Location', 'best', 'AutoUpdate', 'off');
        % Aggiorna linea verticale sullo scree plot
        delete(findobj(ax_pca_scree, 'Tag', 'k_line'));
        xline(ax_pca_scree, k_new, ':r', sprintf('k=%d', k_new), ...
              'LineWidth', 1.5, 'Tag', 'k_line');

        % Aggiorna pannello firma con il passaggio peggiore al nuovo k
        [~, idx_worst] = max(rmse_new);
        plot_signature_comparison_with_k(M, idx_worst, k_new);
    end

 
    function plot_signature_comparison_with_k(M, idx, k_use)
        N = M.N_GRID;

        % Ricostruzione del passaggio nello spazio dei canali (analisi parallela)
        ridx = M.ord_run(idx);                 % passaggio in ordine originale
        rows = (M.run_id == ridx);             % righe (posizioni) di questo passaggio
        recon_chan = (M.scores_full(rows, 1:k_use) * M.coeffs(:, 1:k_use)' + M.mu_pca) ...
                     .* M.sg_ch + M.mu_ch;     % N x n_chan, destandardizzato
        recon_unscaled = nan(1, M.n_chan * N);
        for c = 1:M.n_chan
            cols = (c-1)*N + 1 : c*N;
            recon_unscaled(cols) = recon_chan(:, c).';
        end

        % RMSE specifico di questo passaggio al k corrente
        resid_idx = M.scores_full(rows, k_use+1:end) * M.coeffs(:, k_use+1:end)';
        rmse_idx  = sqrt(mean(resid_idx(:).^2));

        title_str = sprintf('Firma %s - %s | k=%d | RMSE=%.3f', ...
            datestr(M.dates(idx), 'dd/mm/yy'), M.label, k_use, rmse_idx);
        draw_signature_grid(M, M.X_orig(idx, :), recon_unscaled, title_str);
    end


    function plot_signature_comparison(M, idx)
        title_str = sprintf('Firma %s - %s | RMSE=%.3f', ...
            datestr(M.dates(idx), 'dd/mm/yy'), M.label, M.rmse(idx));
        draw_signature_grid(M, M.X_orig(idx, :), M.X_recon(idx, :), title_str);
    end


function draw_signature_grid(M, orig_row, recon_row, title_str)
        % Firma su 6 sottografici, un sensore ciascuno.
        % Ascisse: posizione [m] (M.x_grid, da -WINDOW_SIZE a +WINDOW_SIZE)
        % Ordinate: inviluppo RMS [m/s^2]
        N  = M.N_GRID;
        xg = M.x_grid(:).';
        for c = 1:M.n_chan
            ax = ax_pca_sig(c);
            cla(ax); hold(ax, 'on');
            cols = (c-1)*N + 1 : c*N;
            plot(ax, xg, orig_row(cols),  'b-',  'LineWidth', 1.0);
            plot(ax, xg, recon_row(cols), 'r--', 'LineWidth', 1.0);
            title(ax, M.ch_labels{c}, 'FontWeight', 'normal', 'FontSize', 9);
            grid(ax, 'on'); set(ax, 'FontSize', 8);
            xlim(ax, [xg(1) xg(end)]);
            if c >= 4                          % riga inferiore -> ascisse
                xlabel(ax, 'Posizione [m]', 'FontSize', 8);
            end
            if c == 1 || c == 4                % colonna sinistra -> ordinate
                ylabel(ax, 'Inviluppo RMS [m/s^2]', 'FontSize', 8);
            end
            hold(ax, 'off');
        end
        set(lbl_pca_sig_title, 'String', ...
            [title_str '     blu: originale  ·  rosso tratteggiato: ricostruito']);
    end
% ---------------------------------------------------------------------
    function on_pca_point_click_dynamic(M, rmse_vec)
        cp = get(gca, 'CurrentPoint');
        x_click = cp(1,1); y_click = cp(1,2);
        if gca == ax_pca_anom
            x_range = max(M.dates) - min(M.dates) + eps;
            y_range = max(rmse_vec) - min(rmse_vec) + eps;
            d = ((M.dates - x_click)/x_range).^2 + ((rmse_vec - y_click)/y_range).^2;
        elseif gca == ax_pca_mani
            x_range = max(M.scores(:,1)) - min(M.scores(:,1)) + eps;
            y_range = max(M.scores(:,2)) - min(M.scores(:,2)) + eps;
            d = ((M.scores(:,1) - x_click)/x_range).^2 + ((M.scores(:,2) - y_click)/y_range).^2;
        else
            return;
        end
        [~, idx] = min(d);
        k_curr = round(get(sld_k, 'Value'));
        plot_signature_comparison_with_k(M, idx, k_curr);
    end
    % ---------------------------------------------------------------------


% =========================================================================
    %  CLUSTERING MANIFOLD PCA — finestra separata
    % =========================================================================
    function on_open_pca_clustering(~, ~)
        % --- Modello attivo ---
        if get(pop_pca_dir, 'Value') == 1
            M_cl = PCA_Models.Forward;  dir_label = 'Forward';
        else
            M_cl = PCA_Models.Backward; dir_label = 'Backward';
        end
        
        if isempty(M_cl)
            msgbox(sprintf('Modello PCA %s non disponibile.', dir_label), 'Clustering', 'warn');
            return;
        end

        n_pts = size(M_cl.scores, 1);
        if n_pts < 6
            msgbox('Passaggi insufficienti per il clustering (minimo 6).', 'Clustering', 'warn');
            return;
        end

        def_id = ''; try, def_id = Defect.ID_PK; catch, end

        % --- Figura + dropdown modalità ---
        fig_cl = figure('Name', sprintf('Clustering PCA — %s | %s', def_id, dir_label), ...
            'NumberTitle', 'off', 'Color', 'w', 'Position', [80 60 1400 850]);

        pnl_top = uipanel('Parent', fig_cl, 'Units', 'normalized', ...
            'Position', [0 0.95 0.30 0.05], 'BackgroundColor', 'w', 'BorderType', 'none');
        uicontrol('Parent', pnl_top, 'Style', 'text', 'String', 'Vista:', ...
            'Units', 'normalized', 'Position', [0.03 0.15 0.18 0.6], ...
            'BackgroundColor', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
            
        pop_mode = uicontrol('Parent', pnl_top, 'Style', 'popupmenu', ...
            'String', {'Fasi temporali (mensili)', 'Fasi temporali (bisettimanali)', 'Regimi PCA (K-Means)'}, ...
            'Units', 'normalized', 'Position', [0.24 0.2 0.72 0.6], 'Value', 1);

        % Handle persistenti
        ax_TL = gobjects(1);  ax_TR = gobjects(1);
        sensor_axes = gobjects(1, 6);
        sgt = [];

        set(pop_mode, 'Callback', @(~,~) render());
        render();

        % =====================================================================
        function render()
            % 1. Salviamo il valore della vista PRIMA di cancellare
            v = get(pop_mode, 'Value');

            % 2. Pulizia SELETTIVA DEGLI ASSI (non distrugge i menu)
            delete(findobj(fig_cl, 'Type', 'axes', '-not', 'Tag', 'SensorAx'));
            if ~isempty(sgt) && isgraphics(sgt), delete(sgt); end
            
            % 3. Ricrea Assi Superiori
            ax_TL = axes('Parent', fig_cl, 'Position', [0.06 0.62 0.25 0.28]);
            ax_TR = axes('Parent', fig_cl, 'Position', [0.38 0.62 0.55 0.28]);
            
            % 4. Ricrea la griglia inferiore
            make_sensor_grid_axes();

            % 5. Disegno della modalità scelta
            if     v == 1, render_monthly('month');
            elseif v == 2, render_monthly('biweek');
            else,          render_regimes_logic();
            end
        end

        % =====================================================================
        function render_monthly(gran)
            if strcmp(gran, 'biweek')
                bin = floor((M_cl.dates - min(M_cl.dates)) / 14);
                [~, ~, phase] = unique(bin);
                lbl_fmt = 'dd mmm'; gran_word = 'bisettimanali';
            else
                dv = datevec(M_cl.dates);
                ym = dv(:,1)*12 + dv(:,2);
                [~, ~, phase] = unique(ym);
                lbl_fmt = 'mmm yy'; gran_word = 'mensili';
            end
            
            P = max(phase);
            % Colori blu(early) -> rosso(late)
            tt  = linspace(0, 1, max(P,2))'; tt = tt(1:P);
            pcol = (1-tt).*[0 0.45 0.74] + tt.*[0.85 0.1 0.1];

            % Statistiche per fase
            plabels = cell(1,P); pmid = nan(1,P);
            cent1 = nan(1,P); cent2 = nan(1,P); rmse_ph = nan(1,P);
            for p = 1:P
                m = (phase == p);
                if ~any(m), continue; end
                plabels{p} = datestr(min(M_cl.dates(m)), lbl_fmt);
                pmid(p)    = mean(M_cl.dates(m));
                cent1(p)   = mean(M_cl.scores(m,1));
                cent2(p)   = mean(M_cl.scores(m,2));
                rmse_ph(p) = mean(M_cl.rmse(m));
            end

            draw_top_plots(phase, pcol, pmid, rmse_ph, plabels, cent1, cent2, gran_word);
            draw_sensor_comparison(phase, pcol, plabels);
            
            sgt = sgtitle(fig_cl, sprintf('Evoluzione Fisica per Sensore (Fasi %s) — %s | %s', gran_word, def_id, dir_label), ...
                'FontWeight', 'bold', 'FontSize', 14);
        end

        % =====================================================================
        function render_regimes_logic()
            % K-Means sui primi 2 score PCA
            scores2 = M_cl.scores(:, 1:min(2, size(M_cl.scores, 2)));
            k_best = 3; % Default
            rng(42); 
            [lab, cen] = kmeans(scores2, k_best, 'Replicates', 10);
            clr = lines(k_best);
            
            plabels = arrayfun(@(x) sprintf('Regime %d',x), 1:k_best, 'UniformOutput', false);
            
            % Plot superiori semplificati per regimi
            hold(ax_TL, 'on'); grid(ax_TL, 'on');
            for cc = 1:k_best
                m = (lab == cc);
                scatter(ax_TL, M_cl.dates(m), M_cl.rmse(m), 30, clr(cc,:), 'filled', 'MarkerEdgeColor', 'k');
            end
            datetick(ax_TL, 'x', 'mmm yy'); title(ax_TL, 'RMSE per Regime');
            
            hold(ax_TR, 'on'); grid(ax_TR, 'on');
            for cc = 1:k_best
                m = (lab == cc);
                scatter(ax_TR, scores2(m,1), scores2(m,2), 50, clr(cc,:), 'filled', 'DisplayName', plabels{cc});
            end
            plot(ax_TR, cen(:,1), cen(:,2), 'kx', 'MarkerSize', 12, 'LineWidth', 2);
            title(ax_TR, 'Mappa PC1-PC2 (Cluster di firma)'); legend(ax_TR, 'Location', 'best');

            draw_sensor_comparison(lab, clr, plabels);
            
            sgt = sgtitle(fig_cl, sprintf('Confronto Regimi di Firma (K-Means) — %s | %s', def_id, dir_label), ...
                'FontWeight', 'bold', 'FontSize', 14);
        end

        % =====================================================================
        function draw_top_plots(phase, pcol, pmid, rmse_ph, plabels, cent1, cent2, gran)
            % ax_TL: RMSE
            hold(ax_TL, 'on'); grid(ax_TL, 'on');
            for p = 1:max(phase)
                m = (phase == p); if ~any(m), continue; end
                scatter(ax_TL, M_cl.dates(m), M_cl.rmse(m), 25, pcol(p,:), 'filled', 'MarkerEdgeAlpha', 0.5);
            end
            plot(ax_TL, pmid(~isnan(pmid)), rmse_ph(~isnan(rmse_ph)), 'k-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'k');
            datetick(ax_TL, 'x', 'mmm yy'); ylabel(ax_TL, 'RMSE ricostruzione'); title(ax_TL, 'Evoluzione Errore');

            % ax_TR: Manifold
            hold(ax_TR, 'on'); grid(ax_TR, 'on');
            for p = 1:max(phase)
                m = (phase == p); if ~any(m), continue; end
                scatter(ax_TR, M_cl.scores(m,1), M_cl.scores(m,2), 50, pcol(p,:), 'filled', ...
                    'DisplayName', sprintf('%s (%d pass.)', plabels{p}, sum(m)));
            end
            
            % Traiettoria
            ok = ~isnan(cent1);
            plot(ax_TR, cent1(ok), cent2(ok), 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
            quiver(ax_TR, cent1(find(ok,1,'last')-1), cent2(find(ok,1,'last')-1), ...
                cent1(end)-cent1(end-1), cent2(end)-cent2(end-1), 0, 'Color', 'k', 'MaxHeadSize', 2);
            
            xlabel(ax_TR, 'PC1'); ylabel(ax_TR, 'PC2'); 
            title(ax_TR, sprintf('Deriva nel Manifold PCA (Fasi %s)', gran));
            legend(ax_TR, 'Location', 'eastoutside', 'FontSize', 8);
        end

        % =====================================================================
        function make_sensor_grid_axes()
            delete(findobj(fig_cl, 'Tag', 'SensorAx'));
            m_l = 0.06; m_b = 0.06; g_x = 0.04; g_y = 0.08;
            a_w = (1 - 2*m_l - 2*g_x)/3;
            a_h = (0.45 - m_b - g_y)/2;
            
            for c = 1:6
                row = floor((c-1)/3); % 0 = riga alta, 1 = riga bassa
                col = mod(c-1, 3);
                ax_y = 0.50 - a_h - row*(a_h + g_y);
                % Assegno il tag 'SensorAx' per poterli ripulire facilmente senza toccare i bottoni
                sensor_axes(c) = axes('Parent', fig_cl, 'Position', [m_l + col*(a_w+g_x), ax_y, a_w, a_h], 'Tag', 'SensorAx');
            end
        end

        % =====================================================================
        function draw_sensor_comparison(labels_vec, color_map, legend_names)
            N_g = M_cl.N_GRID;
            xg  = M_cl.x_grid;
            
            % Trova il limite Y globale per uniformare gli assi
            max_y = 0;
            for c = 1:6
                cols = (c-1)*N_g + 1 : c*N_g;
                max_y = max(max_y, max(mean(M_cl.X_orig(:, cols), 1) + std(M_cl.X_orig(:, cols), 0, 1)));
            end

            for c = 1:6
                ax = sensor_axes(c);
                cla(ax); hold(ax, 'on'); grid(ax, 'on');
                cols = (c-1)*N_g + 1 : c*N_g;
                
                unique_labs = unique(labels_vec(~isnan(labels_vec)));
                for i = 1:length(unique_labs)
                    lab_idx = unique_labs(i);
                    mask = (labels_vec == lab_idx);
                    if ~any(mask), continue; end
                    
                    sub_rows = M_cl.X_orig(mask, cols);
                    mu_sig = mean(sub_rows, 1);
                    sd_sig = std(sub_rows, 0, 1);
                    
                    % Ombra Deviazione Standard
                    fill(ax, [xg, fliplr(xg)], [mu_sig + sd_sig, fliplr(mu_sig - sd_sig)], ...
                        color_map(lab_idx,:), 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    
                    % Linea Media
                    plot(ax, xg, mu_sig, 'Color', color_map(lab_idx,:), 'LineWidth', 1.8, ...
                        'DisplayName', legend_names{lab_idx});
                end
                
                title(ax, M_cl.ch_labels{c}, 'FontWeight', 'bold', 'FontSize', 10);
                ylim(ax, [0 max_y * 1.1]);
                xlim(ax, [xg(1) xg(end)]);
                if c > 3, xlabel(ax, 'Posizione [m]'); end
                if mod(c,3) == 1, ylabel(ax, 'Inv. RMS [m/s²]'); end
                
                % Legenda solo sul primo sensore
                if c == 1, legend(ax, 'Location', 'northwest', 'FontSize', 7); end
            end
        end

    end  % on_open_pca_clustering    
    
    
    function s = format_pca_header(Models)
        parts = {};
        for fn = {'Forward', 'Backward'}
            mod = Models.(fn{1});
            if isempty(mod)
                parts{end+1} = sprintf('%s: passaggi insufficienti', fn{1}); %#ok<AGROW>
            else
                parts{end+1} = sprintf('%s: %d passaggi | k=%d | Var %.1f%% | RMSE medio: %.3f', ...
                    fn{1}, mod.n_valid, mod.k, mod.var_k, mod.rmse_mean); %#ok<AGROW>
            end
        end
        s = strjoin(parts, '   |   ');
    end

    % ---------------------------------------------------------------------
    function display_pca_model(M)
        if isempty(M)
            cla(ax_pca_scree); cla(ax_pca_anom); cla(ax_pca_mani);
            for a = ax_pca_sig, cla(a); end
            title(ax_pca_scree, 'Modello non disponibile');
            return;
        end

 
        
        % Aggiorna slider e label per il modello corrente
        max_k_avail = min(50, numel(M.explained));
        min_k = 1;
        set(sld_k, 'Min', min_k, 'Max', max_k_avail, ...
                   'Value', min(M.k, max_k_avail), ...
                   'SliderStep', [1/(max_k_avail-min_k) 5/(max_k_avail-min_k)]);

        % (1) Scree plot
        cla(ax_pca_scree); hold(ax_pca_scree, 'on');
        k_show = min(15, numel(M.explained));
        h_bar  = bar(ax_pca_scree, 1:k_show, M.explained(1:k_show), 'FaceColor', [0.3 0.5 0.8]);
        h_cum  = plot(ax_pca_scree, 1:k_show, cumsum(M.explained(1:k_show)), 'r-o', 'LineWidth', 1.5);
        yline(ax_pca_scree, 95, '--k', '95%');
        % Linea per k corrente (può essere modificata dallo slider)
        xline(ax_pca_scree, M.k, ':r', sprintf('k=%d', M.k), ...
              'LineWidth', 1.5, 'Tag', 'k_line');
        xlabel(ax_pca_scree, 'Componente'); ylabel(ax_pca_scree, '% Varianza');
        title(ax_pca_scree, sprintf('Scree Plot (%s)', M.label));
        grid(ax_pca_scree, 'on'); ylim(ax_pca_scree, [0 100]);
        legend([h_bar, h_cum], {'Individuale','Cumulativa'}, 'Location', 'east');

        % (2) Anomaly score (RMSE) vs tempo
        cla(ax_pca_anom, 'reset'); hold(ax_pca_anom, 'on');
        legend(ax_pca_anom, 'off');
        try
            for ax = [ax_pca_anom, ax_pca_sig, ax_pca_mani]
                delete(findall(ax, 'Type', 'datatip'));
            end
        catch
        end

        %datatip anomaly score
        h_anom_pts = scatter(ax_pca_anom, M.dates, M.rmse, 35, M.amps, 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 0.3, ...
            'ButtonDownFcn', @(s,e) on_pca_point_click(M));
        h_anom_pts.DataTipTemplate.DataTipRows = [
            dataTipTextRow('Data', datetime(M.dates, 'ConvertFrom', 'datenum'), 'dd/MM/yy')
            dataTipTextRow('RMSE',       M.rmse,          '%.4f')
            dataTipTextRow('Peak RMS',   M.amps,          '%.2f m/s²')
            dataTipTextRow('Canale peak', M.ch_labels(M.peak_chan_idx)')
            ];

        thr = M.rmse_mean + 2*std(M.rmse);

        % Trend lineare
        t_norm = M.dates - M.dates(1);
        p_fit  = polyfit(t_norm, M.rmse, 1);
        h_trend = plot(ax_pca_anom, M.dates, polyval(p_fit, t_norm), ...
            'r-', 'LineWidth', 2);

        % Media mobile
        w_win = max(3, round(length(M.dates)/15));
        h_mov = plot(ax_pca_anom, M.dates, movmean(M.rmse, w_win), ...
            'k-', 'LineWidth', 1.5);

        yline(ax_pca_anom, thr, '--r', '\mu + 2\sigma', 'LineWidth', 1.2);
        yline(ax_pca_anom, M.rmse_mean, ':k', '\mu', 'LineWidth', 1);
        datetick(ax_pca_anom, 'x', 'dd/mm/yy', 'keeplimits');
        xlabel(ax_pca_anom, 'Data'); ylabel(ax_pca_anom, 'RMSE ricostruzione');
        slope_per_day = p_fit(1);
        title(ax_pca_anom, sprintf(['Anomaly Score (k=%d, \\mu=%.3f, ', ...
            'trend=%+.5f/giorno) - %s'], ...
            M.k, M.rmse_mean, slope_per_day, M.label));
        grid(ax_pca_anom, 'on');
        cb = colorbar(ax_pca_anom);
        cb.Label.String = 'Max RMS 0.5m tra i sensori [m/s^2]';
        cb.Label.Interpreter = 'tex';
        legend([h_trend, h_mov], {'Trend lineare', sprintf('Media mobile w=%d', w_win)}, ...
            'Location', 'best', 'AutoUpdate', 'off');

        % (3) Manifold 3D PC1-PC2-Tempo (colore = tempo, size = RMSE)
        cla(ax_pca_mani, 'reset');
        try, delete(findall(ax_pca_mani, 'Type', 'datatip')); catch, end

        % --- Ordine cronologico e variabili base ---
        [dates_sorted, ord] = sort(M.dates);
        pc1_s    = M.scores(ord, 1);
        pc2_s    = M.scores(ord, 2);
        rmse_s   = M.rmse(ord);
        ch_s_idx = M.peak_chan_idx(ord);
        days_t   = dates_sorted - dates_sorted(1);

        % --- Aggregazione settimanale (centroidi + RMSE medio) ---
        WEEK_BIN  = 7;                                % giorni per bin (modificabile)
        week_id   = floor(days_t / WEEK_BIN);
        uw        = unique(week_id);
        n_weeks   = length(uw);
        cent_pc1  = zeros(n_weeks, 1);
        cent_pc2  = zeros(n_weeks, 1);
        cent_t    = zeros(n_weeks, 1);
        cent_rmse = zeros(n_weeks, 1);
        for w = 1:n_weeks
            mw = (week_id == uw(w));
            cent_pc1(w)  = mean(pc1_s(mw));
            cent_pc2(w)  = mean(pc2_s(mw));
            cent_t(w)    = mean(days_t(mw));
            cent_rmse(w) = mean(rmse_s(mw));
        end

        % --- Mappa dimensione marker su RMSE (5..50 pt²) ---
        rmin = min(rmse_s); rmax = max(rmse_s);
        size_fun = @(r) 5 + 45 * (r - rmin) ./ max(rmax - rmin, eps);
        sz_pts   = size_fun(rmse_s);
        sz_cent  = size_fun(cent_rmse) * 3;            % centroidi più grandi

        hold(ax_pca_mani, 'on');

        % --- Strato 1: nuvola dei passaggi singoli (sfondo, semi-trasparente) ---
        h_cloud = scatter3(ax_pca_mani, pc1_s, pc2_s, days_t, sz_pts, days_t, ...
            'filled', 'MarkerFaceAlpha', 0.25, 'MarkerEdgeAlpha', 0);
        h_cloud.DataTipTemplate.DataTipRows = [
            dataTipTextRow('PC1',     pc1_s,    '%.2f')
            dataTipTextRow('PC2',     pc2_s,    '%.2f')
            dataTipTextRow('Giorni',  days_t,   '%.0f')
            dataTipTextRow('RMSE',    rmse_s,   '%.4f')
            dataTipTextRow('Data',    datetime(dates_sorted, 'ConvertFrom', 'datenum'), 'dd/MM/yy')
            dataTipTextRow('Canale peak', M.ch_labels(ch_s_idx)')
            ];

        % --- Strato 2: traiettoria settimanale (linea spessa fra i centroidi) ---
        plot3(ax_pca_mani, cent_pc1, cent_pc2, cent_t, '-', ...
            'Color', [0.3 0.3 0.3 0.7], 'LineWidth', 1.5, 'HandleVisibility', 'off');

        % --- Strato 3: centroidi settimanali (marker grossi e ben visibili) ---
        h_cent = scatter3(ax_pca_mani, cent_pc1, cent_pc2, cent_t, sz_cent, cent_t, ...
            'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.6);
        h_cent.DataTipTemplate.DataTipRows = [
            dataTipTextRow('PC1 medio',  cent_pc1,  '%.2f')
            dataTipTextRow('PC2 medio',  cent_pc2,  '%.2f')
            dataTipTextRow('Giorno medio', cent_t,  '%.0f')
            dataTipTextRow('RMSE medio', cent_rmse, '%.4f')
            dataTipTextRow('N. settimana', (1:n_weeks)', '%d')
            ];

         % --- Strato 4: drift netto (corda centroide iniziale → finale) ---
        % NB: niente quiver3 — su assi con scale molto diverse (PC ~±1 vs giorni ~100)
        % la testa viene dimensionata sul modulo del vettore (dominato dai giorni)
        % e disegnata in unità dati: le barbe finiscono fuori scala.
        if n_weeks >= 2
            p0 = [cent_pc1(1),   cent_pc2(1),   cent_t(1)];
            p1 = [cent_pc1(end), cent_pc2(end), cent_t(end)];
            plot3(ax_pca_mani, [p0(1) p1(1)], [p0(2) p1(2)], [p0(3) p1(3)], ...
                '--', 'Color', [0.8 0 0 0.5], 'LineWidth', 1.5, 'HandleVisibility', 'off');
            plot3(ax_pca_mani, p1(1), p1(2), p1(3), '^', ...
                'MarkerFaceColor', [0.8 0 0], 'MarkerEdgeColor', [0.8 0 0], ...
                'MarkerSize', 9, 'HandleVisibility', 'off');
        end
       % --- Etichette PC1/PC2 su ogni centroide settimanale ---
        % clamp dei valori microscopici per non stampare "-0.00"
        c1p = cent_pc1; c1p(abs(c1p) < 5e-3) = 0;
        c2p = cent_pc2; c2p(abs(c2p) < 5e-3) = 0;
        for w = 1:n_weeks
            if w == 1
                lbl = sprintf('  %s\n  PC=(%+.2f, %+.2f)', ...
                    datestr(dates_sorted(1), 'dd/mm/yy'), c1p(1), c2p(1));
                col = [0 0.5 0];     fw = 'bold';   fs = 9;
                v_align = 'top';
            elseif w == n_weeks
                lbl = sprintf('  %s\n  PC=(%+.2f, %+.2f)', ...
                    datestr(dates_sorted(end), 'dd/mm/yy'), c1p(end), c2p(end));
                col = [0.6 0 0];     fw = 'bold';   fs = 9;
                v_align = 'bottom';
            else
                lbl = sprintf('  (%+.2f, %+.2f)', c1p(w), c2p(w));
                col = [0.25 0.25 0.25]; fw = 'normal'; fs = 8;
                v_align = 'bottom';
            end
            text(ax_pca_mani, cent_pc1(w), cent_pc2(w), cent_t(w), lbl, ...
                'FontSize', fs, 'FontWeight', fw, 'Color', col, ...
                'VerticalAlignment', v_align);
        end

        % --- Correlazioni nel titolo (invariate) ---
        if length(days_t) >= 3 && std(days_t) > 0
            r_t_pc1  = corr(days_t, pc1_s,  'type', 'Pearson');
            r_t_pc2  = corr(days_t, pc2_s,  'type', 'Pearson');
            r_t_rmse = corr(days_t, rmse_s, 'type', 'Pearson');
            title_str = sprintf(['Manifold 3D — traiettoria settimanale (%d settimane)  |  ', ...
                'r(t,PC1)=%+.2f   r(t,PC2)=%+.2f   r(t,RMSE)=%+.2f'], ...
                n_weeks, r_t_pc1, r_t_pc2, r_t_rmse);
        else
            title_str = 'Manifold 3D — dati insufficienti';
        end

        xlabel(ax_pca_mani, sprintf('PC1 (%.1f%%)', M.explained(1)));
        ylabel(ax_pca_mani, sprintf('PC2 (%.1f%%)', M.explained(2)));
        zlabel(ax_pca_mani, 'Giorni dalla prima corsa');
        title(ax_pca_mani, title_str, 'FontWeight', 'bold');
        grid(ax_pca_mani, 'on');
        apply_pca_view();
        rotate3d(ax_pca_mani, 'on');
        colormap(ax_pca_mani, parula);                 % gradiente percettivo del tempo
        cb3 = colorbar(ax_pca_mani);
        cb3.Label.String = 'Giorni dalla prima corsa';
        hold(ax_pca_mani, 'off');
        % (4) Confronto firma originale vs ricostruita - passaggio peggiore di default
        [~, idx_worst] = max(M.rmse);
        plot_signature_comparison(M, idx_worst);
    end

% ---------------------------------------------------------------------
    % function plot_signature_comparison(M, idx)
    %     cla(ax_pca_sig); hold(ax_pca_sig, 'on');
    %     N = M.N_GRID;
    %     x_full = nan(1, M.n_chan * N);
    %     tick_centers = nan(1, M.n_chan);
    %     for c = 1:M.n_chan
    %         cols = (c-1)*N + 1 : c*N;
    %         % Asse "concatenato" con offset di canale per visualizzazione
    %         x_full(cols) = (c-1) * (2*h.CFG.WINDOW_SIZE + 2) + (M.x_grid + h.CFG.WINDOW_SIZE);
    %         tick_centers(c) = (c-1) * (2*h.CFG.WINDOW_SIZE + 2) + h.CFG.WINDOW_SIZE;
    %         % Separatori tra canali
    %         if c > 1
    %             xline(ax_pca_sig, x_full(cols(1)) - 1, ':', 'Color', [0.5 0.5 0.5]);
    %         end
    %     end
    %     h_orig  = plot(ax_pca_sig, x_full, M.X_orig(idx, :),  'b-',  'LineWidth', 1.2);
    %     h_recon = plot(ax_pca_sig, x_full, M.X_recon(idx, :), 'r--', 'LineWidth', 1.2);
    %     set(ax_pca_sig, 'XTick', tick_centers, 'XTickLabel', M.ch_labels);
    %     ylabel(ax_pca_sig, 'Inviluppo RMS [m/s^2]');
    %     title(ax_pca_sig, sprintf('Firma %s - %s | RMSE=%.3f', ...
    %         datestr(M.dates(idx), 'dd/mm/yy'), M.label, M.rmse(idx)));
    %     grid(ax_pca_sig, 'on');
    %     legend([h_orig, h_recon], {'Originale', 'Ricostruito'}, 'Location', 'best');
    % end

    % ---------------------------------------------------------------------
    function on_pca_point_click(M)
        cp = get(gca, 'CurrentPoint');
        x_click = cp(1,1); y_click = cp(1,2);
        % Determina su quale asse siamo
        if gca == ax_pca_anom
            % Distanza in spazio (data, rmse) — normalizza scala
            x_range = max(M.dates) - min(M.dates) + eps;
            y_range = max(M.rmse)  - min(M.rmse)  + eps;
            d = ((M.dates - x_click)/x_range).^2 + ((M.rmse - y_click)/y_range).^2;
        elseif gca == ax_pca_mani
            x_range = max(M.scores(:,1)) - min(M.scores(:,1)) + eps;
            y_range = max(M.scores(:,2)) - min(M.scores(:,2)) + eps;
            d = ((M.scores(:,1) - x_click)/x_range).^2 + ((M.scores(:,2) - y_click)/y_range).^2;
        else
            return;
        end
        [~, idx] = min(d);
        plot_signature_comparison(M, idx);
    end

    % ---------------------------------------------------------------------
    function on_pca_dir_change(src, ~)
        v = get(src, 'Value');
        if v == 1
            display_pca_model(PCA_Models.Forward);
        else
            display_pca_model(PCA_Models.Backward);
        end
    end


    function apply_pca_view()
        % Imposta la camera del manifold in base al popup Vista.
        % Assi: X = PC1, Y = PC2, Z = giorni.
        try
            mode = get(pop_pca_view, 'Value');
        catch
            mode = 1;   % default 3D se il popup non esiste ancora
        end
        switch mode
            case 2   % PC1 vs Tempo: PC1 in ascissa, giorni in ordinata
                view(ax_pca_mani, 0, 0);
            case 3   % PC2 vs Tempo: PC2 in ascissa, giorni in ordinata
                view(ax_pca_mani, 90, 0);
            otherwise % 3D
                view(ax_pca_mani, 45, 25);
        end
    end

    function on_pca_view_change(~, ~)
        apply_pca_view();
    end
    % =====================================================================
    % NUOVA TAB 8: AUTOENCODER (AI PREDICTIVE MAINTENANCE)
    % =====================================================================
    tab_ae = uitab(tabgp, 'Title', 'Autoencoder (AI)');
    
    % --- Pannello Controlli ---
    pnl_ae_ctrl = uipanel('Parent', tab_ae, 'Position', [0.01 0.88 0.98 0.11], 'BackgroundColor', 'w', 'BorderType', 'none');
    
    uicontrol('Parent', pnl_ae_ctrl, 'Style', 'text', 'String', 'Modello AI:', ...
        'Units', 'normalized', 'Position', [0.01 0.3 0.08 0.4], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'right', 'FontWeight', 'bold');
        
    btn_load_model = uicontrol('Parent', pnl_ae_ctrl, 'Style', 'pushbutton', 'String', 'Carica Modello MAT', ...
        'Units', 'normalized', 'Position', [0.10 0.3 0.12 0.4], 'Callback', @load_ae_model);
        
    lbl_model_status = uicontrol('Parent', pnl_ae_ctrl, 'Style', 'text', 'String', ' Nessun modello caricato', ...
        'Units', 'normalized', 'Position', [0.23 0.3 0.20 0.4], 'BackgroundColor', 'w', ...
        'ForegroundColor', [0.6 0 0], 'HorizontalAlignment', 'left', 'FontAngle', 'italic');
        
    btn_run_ae = uicontrol('Parent', pnl_ae_ctrl, 'Style', 'pushbutton', 'String', 'Esegui Analisi su Storico', ...
        'Units', 'normalized', 'Position', [0.45 0.3 0.18 0.4], 'BackgroundColor', [0.8 1 0.8], ...
        'FontWeight', 'bold', 'Callback', @run_ae_inference, 'Enable', 'off');
        
    % --- Assi Grafici ---
    % 1. Evoluzione Anomaly Score (Curva di degradazione)
    ax_ae_trend = axes('Parent', tab_ae, 'Position', [0.06 0.52 0.88 0.34]);
    grid(ax_ae_trend, 'on'); hold(ax_ae_trend, 'on');
    title(ax_ae_trend, 'Curva di Degradazione (Anomaly Score - MSE) nel Tempo', 'FontWeight', 'bold', 'FontSize', 11);
    xlabel(ax_ae_trend, 'Data'); ylabel(ax_ae_trend, 'Mean Squared Error (MSE)');
    
   % 2. Confronto Originale vs Ricostruito (Ultima Run)
    pnl_ae_signal = uipanel('Parent', tab_ae, 'Position', [0.02 0.02 0.96 0.44], 'BackgroundColor', 'w', 'BorderType', 'none');
    
    % Etichetta testuale che farà da Titolo Dinamico
    uicontrol('Parent', pnl_ae_signal, 'Style', 'text', 'Tag', 'AE_Title_Lbl', ...
              'String', 'Firma Sensori: Originale vs Ricostruito (Clicca un punto nel grafico sopra)', ...
              'Units', 'normalized', 'Position', [0 0.90 1 0.1], 'BackgroundColor', 'w', 'FontWeight', 'bold', 'FontSize', 11);
              
    % Array di 4 Assi
    ax_ae_signal = gobjects(4,1);
    w_ax = 0.225; gap = 0.02;
    for c = 1:4
        ax_ae_signal(c) = axes('Parent', pnl_ae_signal, 'Position', [(c-1)*(w_ax+gap)+0.03, 0.15, w_ax, 0.70]);
        grid(ax_ae_signal(c), 'on'); hold(ax_ae_signal(c), 'on');
    end
   





    % =====================================================================
    % FUNZIONI HELPER
    % =====================================================================
% --- FUNZIONE HELPER PER LAMBDA VELOCE ---
    function lam = get_quick_lambda_local(sig, NFFT, fs)
        if isempty(sig) || length(sig) < 4
            lam = 0; return; 
        end
        % Estrae il centro del segnale se è più lungo di NFFT
        if length(sig) > NFFT
            st = floor((length(sig) - NFFT)/2) + 1;
            sig = sig(st : st + NFFT - 1);
        end
        [pxx, f] = periodogram(sig, hamming(length(sig)), NFFT, fs);
        [~, idx] = max(pxx);
        if f(idx) < 0.05
            lam = 0; % Frequenza irrilevante
        else
            lam = 1 / f(idx);
            if lam > 15, lam = 0; end % Limite di sicurezza
        end
    end
% --- AGGIORNAMENTO STFT (Scala coerente su TUTTE le run) ---
    function update_stft(~, ~)
        delete(allchild(pnl_stft_plot));
        
        % 1. Aggiorna l'etichetta del cursore dB
        dyn_range = round(get(sld_db, 'Value'));
        set(lbl_db, 'String', sprintf('%d dB', dyn_range));
        sel_idx = get(pop_stft_sens, 'Value'); 
        run_idx = get(pop_stft_run, 'Value');
        win_m = str2double(get(edit_win_size, 'String')); 
        if isnan(win_m) || win_m<=0, win_m=0.1; end
        
        run_data = RawDataStore(run_idx); 
        axis_x = run_data.Axis; 
        if isempty(axis_x), text(0.5,0.5,'No Spatial Data','Parent',axes('Parent',pnl_stft_plot)); return; end
        
        dx_local = mean(diff(axis_x)); 
        if isnan(dx_local) || dx_local==0, dx_local=0.01; end
        fs_space = 1 / dx_local;
        
        % --- PARAMETRI STFT ---
        window = round(win_m * fs_space);     
        if window < 4, window = 4; end        
        noverlap = round(window * 0.90);      % 90% Overlap
        nfft = window;                        % Niente zero-padding
        % ----------------------

        % --- NUOVO: PRE-SCAN MASSIMO GLOBALE SU *TUTTE* LE RUN ---
        global_max_dB = -inf;
        if sel_idx == 1
            sensors_to_scan = 1:8; % Overview: cerchiamo il max su tutti i sensori
        else
            sensors_to_scan = sel_idx - 1; % Zoom: cerchiamo il max solo per quel sensore
        end
        
        % Scorre lo storico completo del singolo difetto per calcolare il vero tetto massimo
        for r = 1:length(RawDataStore)
            for s = sensors_to_scan
                sn = sensor_fields_list{s};
                if isfield(RawDataStore(r).Signals, sn)
                    sig_test = RawDataStore(r).Signals.(sn);
                    if ~isempty(sig_test) && any(sig_test)
                        [S_test, ~, ~] = spectrogram(sig_test, hamming(window), noverlap, nfft, fs_space);
                        P_test_dB = 10 * log10(abs(S_test).^2 + eps);
                        if max(P_test_dB(:)) > global_max_dB
                            global_max_dB = max(P_test_dB(:));
                        end
                    end
                end
            end
        end
        
        if isinf(global_max_dB), global_max_dB = 0; end % Fallback di sicurezza
        global_min_dB = global_max_dB - dyn_range;
        % ---------------------------------------------------------
        
        if sel_idx == 1 % --- OVERVIEW 2x4 ---
            STFT_Cache = cell(8,1); 
            
            % CALCOLO STFT SOLO PER LA RUN CORRENTE DA PLOTTARE
            for k = 1:8
                sens_name = sensor_fields_list{k};
                if isfield(run_data.Signals, sens_name)
                    sig = run_data.Signals.(sens_name);
                    if ~isempty(sig) && any(sig)
                        [S, F, T] = spectrogram(sig, hamming(window), noverlap, nfft, fs_space);
                        P_dB = 10 * log10(abs(S).^2 + eps);
                        STFT_Cache{k} = struct('P_dB', P_dB, 'F', F, 'T', T);
                    end
                end
            end
            
            % PLOT OVERVIEW
            for k = 1:8
                ax = subplot(4, 2, k, 'Parent', pnl_stft_plot);
                if ~isempty(STFT_Cache{k})
                    P_dB = STFT_Cache{k}.P_dB;
                    F    = STFT_Cache{k}.F;
                    T    = STFT_Cache{k}.T;
                    T_rel = T + min(axis_x);
                    imagesc(ax, T_rel, F, P_dB);
                    axis(ax, 'xy'); colormap(ax, jet);
                    
                    % Usa i limiti globali assoluti
                    try clim(ax, [global_min_dB, global_max_dB]); catch, caxis(ax, [global_min_dB, global_max_dB]); end
                    
                    xline(ax, 0, 'w--', 'LineWidth', 1.5);
                    xtickformat(ax, '%.1f');
                    
                    c = colorbar(ax);
                    ylabel(c, 'dB', 'FontSize', 8, 'FontWeight', 'bold');
                    title(ax, sensor_titles_dropdown{k}, 'FontSize', 8, 'FontWeight', 'bold');
                    
                    y_ticks = get(ax, 'YTick');
                    y_labels = cell(size(y_ticks));
                    for yt = 1:length(y_ticks)
                        if y_ticks(yt) == 0, y_labels{yt} = '0';
                        else, y_labels{yt} = sprintf('%.1f [%.2fm]', y_ticks(yt), 1/y_ticks(yt)); end
                    end
                    set(ax, 'YTickLabel', y_labels);
                    if k > 6, xlabel(ax, 'Posizione [m]', 'FontSize', 8); end
                    if mod(k, 2) == 1, ylabel(ax, 'Freq [1/m]  [\lambda]', 'FontSize', 8); end
                else
                    text(ax, 0.5, 0.5, 'No Signal', 'HorizontalAlignment', 'center');
                    title(ax, sensor_titles_dropdown{k}, 'FontSize', 8, 'FontWeight', 'bold');
                end
            end
            
        else % --- ZOOM SINGOLO ---
            real_sens_idx = sel_idx - 1; 
            sens_name = sensor_fields_list{real_sens_idx};
            ax = axes('Parent', pnl_stft_plot, 'Position', [0.10 0.15 0.80 0.75]);
            
            if isfield(run_data.Signals, sens_name)
                sig = run_data.Signals.(sens_name);
                if ~isempty(sig) && any(sig)
                    [S, F, T] = spectrogram(sig, hamming(window), noverlap, nfft, fs_space);
                    T_rel = T + min(axis_x);
                    P_dB = 10 * log10(abs(S).^2 + eps);
                    
                    imagesc(ax, T_rel, F, P_dB); 
                    axis(ax, 'xy'); colormap(ax, jet); 
                    
                    % Usa i limiti globali assoluti calcolati nel pre-scan!
                    try clim(ax, [global_min_dB, global_max_dB]); catch, caxis(ax, [global_min_dB, global_max_dB]); end
                    
                    xline(ax, 0, 'w--', 'LineWidth', 1.5);
                    
                    c = colorbar(ax);
                    ylabel(c, 'Densità Spettrale [dB]', 'FontSize', 10, 'FontWeight', 'bold');
                    
                    title(ax, sensor_titles_dropdown{real_sens_idx}, 'FontSize', 12, 'FontWeight', 'bold');
                    xlabel(ax, 'Posizione Relativa [m]', 'FontSize', 10, 'FontWeight', 'bold'); 
                    
                    y_ticks = get(ax, 'YTick');
                    y_labels = cell(size(y_ticks));
                    for yt = 1:length(y_ticks)
                        if y_ticks(yt) == 0, y_labels{yt} = '0';
                        else, y_labels{yt} = sprintf('%.1f  [ \\lambda = %.2f m ]', y_ticks(yt), 1/y_ticks(yt)); end
                    end
                    set(ax, 'YTickLabel', y_labels);
                    ylabel(ax, 'Freq. Spaziale [cicli/m]  &  Lunghezza d''onda [\lambda]', 'FontSize', 10, 'FontWeight', 'bold');
                else
                    text(ax, 0.5, 0.5, 'Segnale Assente o Vuoto', 'HorizontalAlignment', 'center', 'FontSize', 14);
                end
            end
        end
    end



function update_psd(~, ~)
        % 1. Recupero parametri
        sens_idx = get(pop_psd_sens, 'Value');
        sens_name = sensor_fields_list{sens_idx};
        current_run_idx = get(pop_psd_run, 'Value');
        
        set(pop_stft_run, 'Value', current_run_idx); 
        
        win_m = str2double(get(edit_psd_win, 'String'));
        if isnan(win_m) || win_m <= 0, win_m = 10.0; end
        
        all_pxx = [];
        freq_vec = [];
        pxx_current = [];
        current_date = 'N/D';
        
        % --- PARAMETRI GLOBALI COERENTI CON IL 3D ---
        dx_global = 0.030; % Assicurati che sia uguale in entrambe!
        fs_global = 1 / dx_global;
        NFFT_global = round(win_m / dx_global);
        if NFFT_global < 4, NFFT_global = 4; end
        
        % 2. Ciclo di calcolo su tutte le run
        for r = 1:length(RawDataStore)
            if isfield(RawDataStore(r).Signals, sens_name)
                sig_full = double(RawDataStore(r).Signals.(sens_name));
                axis_full = double(RawDataStore(r).Axis);
                
                if isempty(sig_full) || isempty(axis_full) || (length(sig_full) ~= length(axis_full))
                    continue; 
                end
                
                % RITAGLIO ATTORNO AL PICCO (Centro 0)
                mask = axis_full >= -win_m/2 & axis_full <= win_m/2;
                sig_r = sig_full(mask);
                
                if isempty(sig_r) || length(sig_r) < 4, continue; end
                
                % --- CALCOLO PSD: Hamming + NFFT_global ---
                [pxx_r, f] = periodogram(sig_r, hamming(length(sig_r)), NFFT_global, fs_global);
                
                if isempty(freq_vec), freq_vec = f; end
                
                if r == current_run_idx
                    pxx_current = pxx_r; 
                    current_date = RawDataStore(r).Date;
                else
                    % PLOT STORICO (Grigio)
                    if length(f) == length(pxx_r) 
                        h_line = plot(ax_psd, f, pxx_r, 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'HandleVisibility', 'off');
                        set(h_line, 'UserData', struct('Date', RawDataStore(r).Date, 'Type', 'Storico'));
                        all_pxx = [all_pxx, pxx_r];
                    end
                end
            end
        end
        
        % 3. Media Storica
        if ~isempty(all_pxx) && ~isempty(freq_vec)
            pxx_mean = mean(all_pxx, 2);
            plot(ax_psd, freq_vec, pxx_mean, 'Color', [0.3 0.3 0.3], 'LineStyle', '--', 'LineWidth', 1.2, 'DisplayName', 'Media Storica');
        end
        
        % 4. Run Selezionata
        if ~isempty(pxx_current) && ~isempty(freq_vec)
            h_curr = plot(ax_psd, freq_vec, pxx_current, 'Color', [0.8 0.2 0], 'LineWidth', 2, 'DisplayName', 'Run Selezionata');
            set(h_curr, 'UserData', struct('Date', current_date, 'Type', 'Selezionata'));
        end
        
        % 5. Estetica
        xlabel(ax_psd, 'Frequenza Spaziale [cicli/m]', 'FontWeight', 'bold');
        ylabel(ax_psd, 'PSD [(m/s^2)^2 / (cicli/m)]', 'FontWeight', 'bold');
        grid(ax_psd, 'on');
        
        title(ax_psd, ['Confronto PSD (Finestra: ', num2str(win_m), 'm) - ', sensor_titles_dropdown{sens_idx}], 'FontSize', 12);
        legend(ax_psd, 'Location', 'northeast', 'FontSize', 8);
        
        dcm = datacursormode(ancestor(ax_psd, 'figure'));
        set(dcm, 'UpdateFcn', @master_datatip_fcn);
        
        update_psd_top_axis(ax_psd, tab_psd);
    end

function update_psd_top_axis(main_ax, parent_tab)
    % 1. Cerca se l'asse top esiste già
    ax_top = findobj(parent_tab, 'Tag', 'PsdTopAxis');
    
    % --- LOGICA DI SICUREZZA PER IL 3D ---
    % Se siamo in modalità 3D, l'asse Lambda non ha senso (le X ruotano). Lo eliminiamo.
    if strcmp(PSD_Mode, '3D')
        if ~isempty(ax_top), delete(ax_top); end
        return; 
    end
    
    % 2. Se siamo in 2D e non esiste, lo crea
    if isempty(ax_top)
        ax_top = axes('Parent', parent_tab, 'Position', get(main_ax, 'Position'), ...
            'XAxisLocation', 'top', 'YTick', [], 'Color', 'none', 'Box', 'off', ...
            'Tag', 'PsdTopAxis', 'HitTest', 'off');
    end
    
    % 3. Sincronizza i limiti X e la posizione con l'asse principale
    xl = get(main_ax, 'XLim');
    set(ax_top, 'XLim', xl, 'Position', get(main_ax, 'Position'));
    
    % 4. Calcolo dei Tick (uguale a prima ma più robusto)
    f_max_visible = xl(2);
    if f_max_visible < 10, tick_step = 2;
    elseif f_max_visible < 25, tick_step = 5;
    else, tick_step = 10; end
    
    top_ticks = 0:tick_step:f_max_visible;
    xticklabels_top = cell(size(top_ticks));
    
    for it = 1:length(top_ticks)
        f_val = top_ticks(it);
        if f_val <= 0.01 
            xticklabels_top{it} = 'inf';
        else
            lambda = 1 / f_val;
            if lambda >= 1, xticklabels_top{it} = sprintf('%.1fm', lambda);
            else, xticklabels_top{it} = sprintf('%.2fm', lambda); end
        end
    end
    
    % 5. Applichiamo i tick
    set(ax_top, 'XTick', top_ticks, 'XTickLabel', xticklabels_top, 'FontSize', 8, 'TickDir', 'out');
    xlabel(ax_top, 'Lunghezza d''onda [\lambda = 1/f]', 'FontWeight', 'bold');
end





% --- NUOVA FUNZIONE HELPER: Salto alla Run Critica ---
    function goto_max_run(~, ~)
        % Trova l'indice della run con l'ampiezza massima nello storico
        [~, max_idx] = max([RawDataStore.Amp]);
        
        % Aggiorna l'interfaccia (il menu a tendina)
        set(pop_stft_run, 'Value', max_idx);
        
        % Forza il ricalcolo dello spettrogramma
        update_stft([], []);
    end


    function on_ctrl_change(src, ~)
        if src == sld_win, val = get(src, 'Value'); set(lbl_win, 'String', sprintf('%.2f m', val)); end
        recalc_metrics();
        update_evolutive_plots();
    end
    



function update_evolutive_plots()
    grouping_val = get(pop_grouping, 'Value');
    all_dates_dt = datetime(dates_num, 'ConvertFrom', 'datenum');
    
    switch grouping_val
        case 1
            dates_rounded = all_dates_dt;
        case 2
            dates_rounded = dateshift(all_dates_dt, 'start', 'day');
        case 3
            dates_rounded = dateshift(all_dates_dt - days(1), 'start', 'week') + days(1);
        case 4
            dates_rounded = dateshift(all_dates_dt, 'start', 'month');
    end
    
    [unique_periods, ~, ic] = unique(dates_rounded);
    n_periods = length(unique_periods);
    
    avg_dates       = datenum(unique_periods);
    avg_Ratio_SX_DX = zeros(n_periods, 1);
    avg_Ratio_FR    = zeros(n_periods, 1);
    avg_Ratio_LV    = zeros(n_periods, 1);
    avg_Lambda_All  = zeros(n_periods, 8);
    avg_SX_F        = zeros(n_periods, 1);
    avg_SX_R        = zeros(n_periods, 1);
    avg_DX_F        = zeros(n_periods, 1);
    avg_DX_R        = zeros(n_periods, 1);
    
    for k = 1:n_periods
        mask = (ic == k);
        avg_Ratio_SX_DX(k)  = mean(Ratio_SX_DX(mask), 'omitnan');
        avg_Ratio_FR(k)     = mean(Ratio_FR(mask),     'omitnan');
        avg_Ratio_LV(k)     = mean(Ratio_LV(mask),     'omitnan');
        avg_Lambda_All(k,:) = mean(Lambda_All(mask,:), 1, 'omitnan');
        avg_SX_F(k) = mean(AllAmps(mask, 1), 'omitnan');
        avg_SX_R(k) = mean(AllAmps(mask, 2), 'omitnan');
        avg_DX_F(k) = mean(AllAmps(mask, 3), 'omitnan');
        avg_DX_R(k) = mean(AllAmps(mask, 4), 'omitnan');
    end
    
    ud_3x3 = struct('DateNum', num2cell(avg_dates), ...
                    'SX_F',    num2cell(avg_SX_F),  ...
                    'SX_R',    num2cell(avg_SX_R),  ...
                    'DX_F',    num2cell(avg_DX_F),  ...
                    'DX_R',    num2cell(avg_DX_R));
    
    % =============================================================
    % TAB MATRICE 3x3: ridisegno completo con i dati AGGREGATI
    % =============================================================
    cla(ax_3x3);                 % pulisce senza fare reset degli assi
    delete(findobj(ax_3x3, 'Type', 'ConstantLine'));  % rimuove xline/yline vecchie
    
    hold(ax_3x3, 'on');
    
    % Ridisegna linea traiettoria e scatter con i punti AGGREGATI
    h_line_3x3 = plot(ax_3x3, avg_Ratio_SX_DX, avg_Ratio_FR, '-', ...
        'Color', [0.8 0.8 0.8], 'LineWidth', 1.5, 'HandleVisibility', 'off');
    
    h_scat_3x3 = scatter(ax_3x3, avg_Ratio_SX_DX, avg_Ratio_FR, 60, avg_dates, ...
        'filled', 'MarkerEdgeColor', 'k', 'UserData', ud_3x3);
    
    % Soglie 3x3
    xline(ax_3x3, 2.0, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Left');
    xline(ax_3x3, 0.5, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Right');
    yline(ax_3x3, 2.0, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Front');
    yline(ax_3x3, 0.5, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Rear');
    
    % Etichetta ultimo punto
    if n_periods > 0
        h_text_3x3 = text(ax_3x3, avg_Ratio_SX_DX(end), avg_Ratio_FR(end), ...
            '  ← ATTUALE', 'Color', 'r', 'FontWeight', 'bold');
    end
    
    % Scale, assi, colorbar
    set(ax_3x3, 'XScale', 'log', 'YScale', 'log');
    xlabel(ax_3x3, 'Ratio Laterale (SX / DX)', 'FontWeight', 'bold');
    ylabel(ax_3x3, 'Ratio Longitudinale (Front / Rear)', 'FontWeight', 'bold');
    grid(ax_3x3, 'on');
    colormap(ax_3x3, parula);
    
    % Elimina la vecchia colorbar e ne crea una nuova
    old_cb = findobj(get(ax_3x3, 'Parent'), 'Type', 'ColorBar');
    if ~isempty(old_cb), delete(old_cb); end
    cb = colorbar(ax_3x3);
    
    % Formato data sulla colorbar in base al raggruppamento
    switch grouping_val
        case 1, fmt_cb = 'dd/mm';   agg_str = sprintf('Singole Corse (%d punti)', n_periods);
        case 2, fmt_cb = 'dd/mm';   agg_str = sprintf('Media Giornaliera (%d giorni)', n_periods);
        case 3, fmt_cb = 'mm/yy';   agg_str = sprintf('Media Settimanale (%d settimane)', n_periods);
        case 4, fmt_cb = 'mm/yy';   agg_str = sprintf('Media Mensile (%d mesi)', n_periods);
    end
    datetick(cb, 'y', fmt_cb);
    ylabel(cb, 'Evoluzione Temporale', 'FontWeight', 'bold');
    
    title(ax_3x3, ...
        ['Rapporti FRONT-REAR e LEFT-RIGHT — ' agg_str], ...
        'FontWeight', 'bold');
    
    % =============================================================
    % TAB RAPPORTI LATERALE: aggiorna con dati aggregati
    % =============================================================
    if isvalid(h_plot_lat)
        set(h_plot_lat, 'XData', avg_dates, 'YData', avg_Ratio_LV);
        % Ricalcola i datetick perché il range X è cambiato
        datetick(ax_lat, 'x', 'dd/mm/yy', 'keepticks', 'keeplimits');
    end
    
    % =============================================================
    % TAB EVOLUZIONE LAMBDA: aggiorna con dati aggregati
    % =============================================================
    for s = 1:8
        if isvalid(h_plot_lam(s))
            set(h_plot_lam(s), 'XData', avg_dates, 'YData', avg_Lambda_All(:, s));
        end
    end
    
    if n_periods > 1
        datetick(ax_lam, 'x', 'dd/mm/yy', 'keepticks', 'keeplimits');
    end
    
    % Auto-zoom Y Lambda
    if ~isempty(avg_Lambda_All) && any(avg_Lambda_All(:) > 0)
        max_val = max(avg_Lambda_All(:));
        ylim(ax_lam, [0, max(0.5, max_val * 1.1)]);
    end
end


    function on_graph_change(~, ~), update_dynamic_plot(); end




function update_psd_3d(~, ~)
        
        sens_idx = get(pop_psd_sens, 'Value');
        sens_name = sensor_fields_list{sens_idx};
        win_m = str2double(get(edit_psd_win, 'String'));
        if isnan(win_m) || win_m <= 0, win_m = 10.0; end

        all_dates_dt = datetime(dates_num, 'ConvertFrom', 'datenum');
        % CON QUESTO:
        grouping_val = get(pop_grouping, 'Value');
        switch grouping_val
            case 1
                dates_rounded = all_dates_dt;  % Singole Corse
            case 2
                dates_rounded = dateshift(all_dates_dt, 'start', 'day');
            case 3
                dates_rounded = dateshift(all_dates_dt - days(1), 'start', 'week') + days(1);
            case 4
                dates_rounded = dateshift(all_dates_dt, 'start', 'month');
        end

        [unique_periods, ~, ic] = unique(dates_rounded);
        n_periods = length(unique_periods);
        
        % Contenitori per la matrice 3D
        PSD_Matrix = []; 
        F_Axis = [];
        Y_Date_Axis = datenum(unique_periods);
        n_periods_valid = 0;
        
        % --- PARAMETRI GLOBALI COERENTI CON IL 2D ---
        dx_global = 0.030; % Assicurati che sia uguale in entrambe!
        fs_global = 1 / dx_global;
        NFFT_global = round(win_m / dx_global);
        if NFFT_global < 4, NFFT_global = 4; end
        
        wb = waitbar(0, 'Generazione Waterfall PSD 3D...');
        
        for k = 1:n_periods
            waitbar(k/n_periods, wb);
            idxs = find(ic == k);
            
            period_pxx = [];
            n_valid_runs = 0;  
            
            for j = 1:length(idxs)
                run_idx = idxs(j);
                
                if ~isfield(RawDataStore(run_idx).Signals, sens_name), continue; end
                
                sig_full = double(RawDataStore(run_idx).Signals.(sens_name));
                axis_full = RawDataStore(run_idx).Axis;
                
                if isempty(sig_full) || isempty(axis_full) || length(sig_full) <= 1, continue; end
                if ~any(sig_full), continue; end 
                
                L_min = min(length(sig_full), length(axis_full));
                if L_min < 10, continue; end
                
                sig_full = sig_full(1:L_min);
                axis_full = axis_full(1:L_min);
                
                mask = axis_full >= -win_m/2 & axis_full <= win_m/2;
                sig_r = sig_full(mask);
                
                if isempty(sig_r) || length(sig_r) < 10, continue; end
                
                % --- CALCOLO PSD: Hamming + NFFT_global (Identico al 2D) ---
                [pxx_r, f] = periodogram(sig_r, hamming(length(sig_r)), NFFT_global, fs_global);
                
                if isempty(period_pxx)
                    period_pxx = zeros(size(pxx_r));
                    F_Axis = f;  
                end
                
                if length(pxx_r) == length(period_pxx)
                    period_pxx = period_pxx + pxx_r;
                    n_valid_runs = n_valid_runs + 1;
                end
            end  
            
            if ~isempty(period_pxx) && n_valid_runs > 0
                n_periods_valid = n_periods_valid + 1;
                PSD_Matrix(n_periods_valid, :) = period_pxx' / n_valid_runs;
            end
            
        end  
        
        close(wb);
        
        if isempty(PSD_Matrix) || n_periods_valid == 0
            delete(allchild(pnl_stft_plot));
            ax_tmp = axes('Parent', pnl_stft_plot);
            text(ax_tmp, 0.5, 0.5, sprintf('Nessun dato disponibile per %s', sensor_titles_dropdown{sens_idx}), ...
                'HorizontalAlignment', 'center', 'FontSize', 14, 'Color', [0.8 0 0]);
            axis(ax_tmp, 'off');
            return;
        end
        
        Y_Date_Axis_valid = Y_Date_Axis(1:n_periods_valid);
        
        h_wf = waterfall(ax_psd, F_Axis, Y_Date_Axis_valid, PSD_Matrix);
        set(h_wf, 'LineWidth', 1.2, 'EdgeColor', 'interp', 'FaceAlpha', 0.7);
        
        view(ax_psd, -37.5, 30); % Vista 3D (tre quarti)
        grid(ax_psd, 'on');
        colormap(ax_psd, jet);
        colorbar(ax_psd);
        
        datetick(ax_psd, 'y', 'mmm yy', 'keeplimits');
        ytickangle(ax_psd, 0); 
        xlabel(ax_psd, 'Frequenza Spaziale [cicli/m]', 'FontWeight', 'bold');
        ylabel(ax_psd, 'Evoluzione Temporale', 'FontWeight', 'bold');
        zlabel(ax_psd, 'PSD Power', 'FontWeight', 'bold');
        title(ax_psd, sprintf('Evoluzione PSD 3D - %s (Win: %.1fm)', ...
            sensor_titles_dropdown{sens_idx}, win_m));
            
        dcm = datacursormode(ancestor(ax_psd, 'figure'));
        set(dcm, 'Enable', 'on', 'UpdateFcn', @master_datatip_fcn);
        
        delete(findobj(ancestor(ax_psd, 'figure'), 'Tag', 'PsdTopAxis'));
    end
% --- Helper: Tooltip con date formattate per Finestra Analisi ---


function txt = master_datatip_fcn(~, event_obj)
    pos = event_obj.Position;
    target = event_obj.Target;
    ax = ancestor(target, 'axes');
    
    % --- 1. Controllo PSD 2D (dal vecchio psd_datatip_fcn) ---
    % Recupera i dati iniettati nella linea
    info = get(target, 'UserData');
    if isstruct(info) && isfield(info, 'Type') && isfield(info, 'Date')
        d_str = datestr(info.Date, 'dd/mm/yyyy HH:MM');
        type_str = info.Type;
        
        lambda = 0; if pos(1) > 0, lambda = 1/pos(1); end
        
        txt = {['Run: ', type_str], ...
               ['Data: ', d_str], ...
               ['Freq: ', num2str(pos(1), '%.2f'), ' cicli/m'], ...
               ['Lambda: ', num2str(lambda, '%.2f'), ' m'], ...
               ['Amp: ', num2str(pos(2), '%.1f')]};
        return; % Trovato! Esce dalla funzione.
    end
    
    % --- 2. Controllo GRAFICI 3D (dal vecchio custom_trend_datatip) ---
    if length(pos) == 3 
        d_val = pos(2);
        
        % Formattazione data
        if abs(d_val - floor(d_val)) < 1e-4 
            date_str = datestr(d_val, 'dd/mm/yy');
        else
            date_str = datestr(d_val, 'dd/mm/yy HH:MM');
        end
        
        % Controlliamo il nome dell'asse X per capire in che grafico siamo
        xlab = get(ax.XLabel, 'String');
        
        if contains(lower(xlab), 'frequenza') || contains(lower(xlab), 'freq')
             % Siamo nel grafico PSD 3D
             txt = {['Data: ', date_str], ...
                    ['Freq: ', num2str(pos(1), '%.2f'), ' cicli/m'], ...
                    ['L. d''onda: ', num2str(1/pos(1), '%.2f'), ' m'], ...
                    ['Power: ', num2str(pos(3), '%.1f')]};
        else
             % Siamo nel grafico Statistiche & Profilo 3D (Posizione)
             txt = {['Data: ', date_str], ...
                    ['Pos: ', num2str(pos(1), '%.2f'), ' m'], ...
                    ['RMS Medio: ', num2str(pos(3), '%.2f'), ' m/s^2']};
        end
        return; % Trovato! Esce dalla funzione.
    end
    
    % --- 3. Controllo GRAFICI 2D Temporali o Matrice 3x3 ---
    if length(pos) == 2 
        % Se X è molto grande (> 700000), è un datenum (Trend, Lat/Vert, Lambda)
        if pos(1) > 700000
            txt = {['Data: ', datestr(pos(1), 'dd/mm/yy')], ...
                   ['Valore: ', num2str(pos(2), '%.2f')]};
        else
            % --- MATRICE 3X3 EVOLUTIVA ---
            ud = get(h_scat_3x3, 'UserData');
            x_data = get(h_scat_3x3, 'XData');
            y_data = get(h_scat_3x3, 'YData');
            
            % Troviamo l'indice esatto del pallino cliccato
            idx = find(abs(x_data - pos(1)) < 1e-4 & abs(y_data - pos(2)) < 1e-4, 1);
            
            if ~isempty(idx) && isstruct(ud)
                d_str = datestr(ud(idx).DateNum, 'dd/mm/yy');
                
                % Formattiamo il testo in modo ordinato e allineato
                txt = {['Data: ', d_str], ...
                       ['Ratio Lat (X): ', num2str(pos(1), '%.2f')], ...
                       ['Ratio Long (Y): ', num2str(pos(2), '%.2f')], ...
                       '--- Componenti Max RMS [m/s^2] ---', ...
                       sprintf('SX Front: %5.1f  |  DX Front: %5.1f', ud(idx).SX_F, ud(idx).DX_F), ...
                       sprintf('SX Rear : %5.1f  |  DX Rear : %5.1f', ud(idx).SX_R, ud(idx).DX_R)};
            else
                % Fallback di sicurezza se clicchi a vuoto
                txt = {['Ratio Lat (X): ', num2str(pos(1), '%.2f')], ...
                       ['Ratio Long (Y): ', num2str(pos(2), '%.2f')]};
            end
        end
    end
end

% --- FUNZIONE PER CAMBIARE MODALITÀ (2D/3D) ---
    function switch_psd_mode(mode)
        PSD_Mode = mode; % Aggiorna la variabile di stato
        refresh_psd_view(); % Forza il ridisegno
    end



% --- INNESCA IL MODELLO AI IN AUTOMATICO ---
    load_ae_model([], []);
    % =====================================================================
    function load_ae_model(~, ~)
        % Percorso fisso
        model_dir = 'C:\Users\Nicco\MATLAB Drive\TESI\Autoencoder_Models';
        
        % Cerca il modello per la tratta corrente
        expected_file = fullfile(model_dir, sprintf('modello_%s.mat', h.CurrentTrackName));
        
        if ~exist(expected_file, 'file')
            set(lbl_model_status, 'String', ' Modello non trovato per questa tratta', 'ForegroundColor', [0.8 0 0]);
            return;
        end
        
        try
            d = load(expected_file);
            
            if isfield(d, 'net') && isfield(d, 'mu_global') && isfield(d, 'sigma_global')
                AE_Net = d.net;
                AE_mu = d.mu_global;
                AE_sigma = d.sigma_global;
                
                % --- NUOVO: RECUPERA v_ref_model SE ESISTE ---
                if isfield(d, 'v_ref_model')
                    AE_v_ref = d.v_ref_model;
                else
                    AE_v_ref = 80; % Fallback
                end
                % ---------------------------------------------
                
                [~, nome_file, ext] = fileparts(expected_file);
                set(lbl_model_status, 'String', [' ' nome_file ext], 'ForegroundColor', [0 0.5 0]);
                set(btn_run_ae, 'Enable', 'on');
                
                % Lancia l'inferenza automaticamente!
                run_ae_inference([], []);
            else
                set(lbl_model_status, 'String', ' Modello MAT non valido', 'ForegroundColor', [0.8 0 0]);
            end
        catch
            set(lbl_model_status, 'String', ' Errore di caricamento', 'ForegroundColor', [0.8 0 0]);
        end
    end


function run_ae_inference(~, ~)
        % =================================================================
        % FASE 0: CONTROLLI INIZIALI
        % =================================================================
        if isempty(AE_Net)
            warndlg('Carica prima il modello MATLAB (.mat)!', 'Attenzione');
            return;
        end
        
        n_history = length(RawDataStore);
        if n_history == 0, return; end
        
        % =================================================================
        % FASE 1: PREPARAZIONE
        % =================================================================
        AE_Results = repmat(struct('DateNum', [], 'MSE', [], 'Original', [], 'Reconstructed', []), n_history, 1);
        ae_sensors = {'left_sensor_front', 'left_sensor_rear', 'right_sensor_front', 'right_sensor_rear'};
        N_SAMPLES_AE = 334;
        
        wb_inf = waitbar(0, 'Esecuzione inferenza IA sullo storico...');
        
        % =================================================================
        % FASE 2: ELABORAZIONE DI OGNI SINGOLA CORSA
        % =================================================================
        for k = 1:n_history
            waitbar(k/n_history, wb_inf);
            run_data = RawDataStore(k);
            
            % FILTRO FORWARD: salta i back (modello allenato solo su forward)
            rms_dx = 0; rms_sx = 0;
            if isfield(run_data.Signals,'right_sensor_front_lat') && ~isempty(run_data.Signals.right_sensor_front_lat)
                rms_dx = rms(double(run_data.Signals.right_sensor_front_lat));
            end
            if isfield(run_data.Signals,'left_sensor_front_lat') && ~isempty(run_data.Signals.left_sensor_front_lat)
                rms_sx = rms(double(run_data.Signals.left_sensor_front_lat));
            end
            
            if ~(rms_dx > rms_sx && rms_dx > 0)
                AE_Results(k).DateNum = datenum(run_data.Date);
                AE_Results(k).MSE     = NaN;
                continue;
            end
            
            % CALCOLO FATTORE QUADRATICO VELOCITÀ
            v_treno = run_data.Speed;
            if isnan(v_treno) || v_treno < 10
                v_treno = AE_v_ref; 
            end
            if isempty(AE_v_ref), AE_v_ref = 80; end 
            K_vel = (v_treno / AE_v_ref)^2;
            
            % INIZIALIZZAZIONE TENSORE MULTI-CANALE (1 x N_SAMPLES_AE x 4)
            multi_channel_sig = zeros(1, N_SAMPLES_AE, length(ae_sensors));
            valid_run = true;
            
            for s = 1:length(ae_sensors)
                sn = ae_sensors{s};
                if isfield(run_data.Signals, sn) && ~isempty(run_data.Signals.(sn))
                    sig = double(run_data.Signals.(sn));
                    sig = sig(:)'; 
                    sig = sig ./ K_vel;
                    if length(sig) ~= N_SAMPLES_AE && length(sig) > 1
                        x_old = linspace(0, 1, length(sig));
                        x_new = linspace(0, 1, N_SAMPLES_AE);
                        sig = interp1(x_old, sig, x_new, 'linear', 'extrap');
                    elseif length(sig) <= 1
                        sig = zeros(1, N_SAMPLES_AE);
                    end
                    sig = sig - mean(sig); 
                else
                    sig = zeros(1, N_SAMPLES_AE);
                    valid_run = false;
                end
                multi_channel_sig(1, :, s) = sig;
            end
            
            % Intelligenza Artificiale (Solo se la corsa è valida)
            if valid_run
                input_norm = (multi_channel_sig - AE_mu) ./ AE_sigma;
                reconstructed = predict(AE_Net, input_norm);
                
                % Errore calcolato appiattendo matematicamente il tensore
                mse_val = mean((input_norm(:) - reconstructed(:)).^2);
                var_original = var(input_norm(:));
                
                if var_original > 0
                    r2_score = 1 - (mse_val / var_original);
                    accuracy_perc = max(0, r2_score) * 100;
                else
                    accuracy_perc = 0;
                end
                
                AE_Results(k).DateNum = datenum(run_data.Date);
                AE_Results(k).MSE = accuracy_perc;
                AE_Results(k).Original = input_norm;
                AE_Results(k).Reconstructed = reconstructed;
            else
                AE_Results(k).DateNum = datenum(run_data.Date);
                AE_Results(k).MSE = NaN; 
            end
        end
        close(wb_inf);
        
        % =================================================================
        % FASE 3: AGGIORNAMENTO GRAFICI
        % =================================================================
        cla(ax_ae_trend);
        
        valid_idx = ~arrayfun(@(x) isempty(x.MSE) || isnan(x.MSE), AE_Results);
        valid_dates = [AE_Results(valid_idx).DateNum];
        valid_accuracy = [AE_Results(valid_idx).MSE]; 
        
        if isempty(valid_accuracy)
            msgbox('Nessun dato valido estratto per l''analisi.', 'Errore');
            return;
        end
        
        h_scatter = plot(ax_ae_trend, valid_dates, valid_accuracy, 'ob', 'MarkerFaceColor', 'b', 'MarkerSize', 5, 'DisplayName', 'Accuratezza Corsa Singola');
        
        if length(valid_accuracy) > 3
            smooth_acc = nan(size(valid_accuracy));
            for ii = 1:length(valid_dates)
                window_mask = valid_dates >= (valid_dates(ii) - 7) & valid_dates <= valid_dates(ii);
                smooth_acc(ii) = mean(valid_accuracy(window_mask));
            end
            plot(ax_ae_trend, valid_dates, smooth_acc, '-r', 'LineWidth', 2, 'DisplayName', 'Trend settimanale');
        end
        
        ylim(ax_ae_trend, [max(0, min(valid_accuracy)-10), 105]); 
        legend(ax_ae_trend, 'Location', 'southwest');
        datetick(ax_ae_trend, 'x', 'dd/mm/yy', 'keeplimits', 'keepticks');
        ylabel(ax_ae_trend, 'Accuratezza Ricostruzione [%]');
        title(ax_ae_trend, 'Curva di Degradazione (Accuratezza di Ricostruzione nel Tempo)', 'FontWeight', 'bold');
        
        try
            valid_raw = RawDataStore(valid_idx);
            valid_amps = [valid_raw.Amp];
            valid_speeds = [valid_raw.Speed];
            
            valid_dirs = cell(1, length(valid_raw));
            for idx_dir = 1:length(valid_raw)
                rms_dx = 0; rms_sx = 0;
                if isfield(valid_raw(idx_dir).Signals, 'right_sensor_front_lat') && ~isempty(valid_raw(idx_dir).Signals.right_sensor_front_lat)
                    rms_dx = rms(double(valid_raw(idx_dir).Signals.right_sensor_front_lat));
                end
                if isfield(valid_raw(idx_dir).Signals, 'left_sensor_front_lat') && ~isempty(valid_raw(idx_dir).Signals.left_sensor_front_lat)
                    rms_sx = rms(double(valid_raw(idx_dir).Signals.left_sensor_front_lat));
                end
                
                if rms_sx > rms_dx, valid_dirs{idx_dir} = 'Back (Indietro)';
                elseif rms_dx > 0 || rms_sx > 0, valid_dirs{idx_dir} = 'Front (Avanti)';
                else, valid_dirs{idx_dir} = 'N/D'; end
            end
            
            id_strs = repmat({Defect.ID_PK}, 1, length(valid_dates));
            date_strs = arrayfun(@(x) datestr(x, 'dd/mm/yy HH:MM'), valid_dates, 'UniformOutput', false);
            
            h_scatter.DataTipTemplate.DataTipRows(1) = dataTipTextRow('PK', id_strs);
            h_scatter.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Data', date_strs);          
            h_scatter.DataTipTemplate.DataTipRows(3) = dataTipTextRow('Marcia', valid_dirs);
            h_scatter.DataTipTemplate.DataTipRows(4) = dataTipTextRow('Accuratezza', valid_accuracy, '%.1f %%'); 
            h_scatter.DataTipTemplate.DataTipRows(5) = dataTipTextRow('Max RMS', valid_amps, '%.1f m/s^2');      
            h_scatter.DataTipTemplate.DataTipRows(6) = dataTipTextRow('Velocità', valid_speeds, '%.0f km/h');    
        catch
        end
        
        set(h_scatter, 'ButtonDownFcn', @(src, evt) on_ae_point_click(src, evt));
        plot_ae_reconstruction(valid_dates(end));
        update_IPI_Score();
        
        function on_ae_point_click(src, evt)
            x_click = evt.IntersectionPoint(1);
            plot_ae_reconstruction(x_click);
            ax_parent = ancestor(src, 'axes');
            delete(findall(ax_parent, 'Type', 'datatip')); 
            x_data = get(src, 'XData'); y_data = get(src, 'YData');
            [~, idx] = min(abs(x_data - x_click)); 
            datatip(src, x_data(idx), y_data(idx)); 
        end
    end
   % function plot_ae_reconstruction(clicked_date)
   %      if isempty(AE_Results), return; end
   % 
   %      % Trova la corsa più vicina alla data cliccata
   %      [~, idx] = min(abs([AE_Results.DateNum] - clicked_date));
   % 
   %      cla(ax_ae_signal);
   %      if isempty(AE_Results(idx).Original) || isnan(AE_Results(idx).MSE), return; end
   % 
   %      % --- MODIFICA: SEPARA IL SEGNALE DALLE VARIABILI DI CONTESTO ---
   %      N_SAMPLES_AE = 334;
   %      n_sensors_features = N_SAMPLES_AE * 4; % I primi 1336 punti sono l'onda
   % 
   %      orig_full = AE_Results(idx).Original;
   %      reco_full = AE_Results(idx).Reconstructed;
   % 
   %      % Ritaglia solo la parte del segnale (Sensori) per il grafico
   %      orig_signal = orig_full(1:n_sensors_features);
   %      reco_signal = reco_full(1:n_sensors_features);
   %      x_axis = 1:n_sensors_features;
   % 
   %      % Plot dei segnali (solo l'onda)
   %      plot(ax_ae_signal, x_axis, orig_signal, 'b', 'LineWidth', 1.2, 'DisplayName', 'Originale');
   %      plot(ax_ae_signal, x_axis, reco_signal, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Ricostruito');
   % 
   %      % Evidenzia l'errore riempiendo l'area tra i due
   %      fill(ax_ae_signal, [x_axis, fliplr(x_axis)], [orig_signal, fliplr(reco_signal)], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'DisplayName', 'Errore (Anomalia)');
   % 
   %      % Linee verticali divisorie tra i 4 sensori
   %      xline(ax_ae_signal, [334, 668, 1002], 'k:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
   % 
   %      % Testi centrati per i sensori
   %      y_max = max(orig_signal);
   %      if y_max < 0.1, y_max = 1; end % Evita che il testo vada fuori scala se il segnale è piatto
   % 
   %      text(ax_ae_signal, 160, y_max*0.9, 'SX Front', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
   %      text(ax_ae_signal, 500, y_max*0.9, 'SX Rear', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
   %      text(ax_ae_signal, 835, y_max*0.9, 'DX Front', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
   %      text(ax_ae_signal, 1170, y_max*0.9, 'DX Rear', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
   % 
   %      legend(ax_ae_signal, 'Location', 'northeast');
   % 
   %      % Informazione extra se ci sono parametri di contesto (Speed e Curve)
   %      extra_info = '';
   %      if length(orig_full) > n_sensors_features
   %          extra_info = ' (Include Speed & Curve)';
   %      end
   % 
   %      % In fondo alla funzione plot_ae_reconstruction:
   %      title(ax_ae_signal, sprintf('Analisi Run: %s (Accuratezza: %.1f%%)%s', ...
   %            datestr(AE_Results(idx).DateNum, 'dd/mm/yy HH:MM'), AE_Results(idx).MSE, extra_info));
   % 
   %              axis(ax_ae_signal, 'tight');
   %  end

function plot_ae_reconstruction(clicked_date)
        if isempty(AE_Results), return; end
        
        % Trova la corsa più vicina alla data cliccata
        [~, idx] = min(abs([AE_Results.DateNum] - clicked_date));
        
        % Pulisce i 4 assi simultaneamente
        arrayfun(@cla, ax_ae_signal);
        
        if isempty(AE_Results(idx).Original) || isnan(AE_Results(idx).MSE), return; end
        
        % Estraiamo i tensori 3D [1 x 334 x 4]
        orig_3d = AE_Results(idx).Original;
        reco_3d = AE_Results(idx).Reconstructed;
        
        sens_names = {'SX Front', 'SX Rear', 'DX Front', 'DX Rear'};
        
        % Troviamo il range Y globale per uniformare gli assi visivamente
        y_max = max(orig_3d(:));
        y_min = min(orig_3d(:));
        range_y = y_max - y_min;
        if range_y < 1e-6, range_y = 1; end
        y_lims = [y_min - 0.2*range_y, y_max + 0.3*range_y];
        
        x_axis = 1:size(orig_3d, 2); % Da 1 a 334
        
        % Ciclo per disegnare i 4 grafici separati
        for c = 1:4
            orig_sig = orig_3d(1, :, c);
            reco_sig = reco_3d(1, :, c);
            
            ax = ax_ae_signal(c);
            
            % Plot delle linee
            plot(ax, x_axis, orig_sig, 'b', 'LineWidth', 1.2, 'DisplayName', 'Originale');
            plot(ax, x_axis, reco_sig, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Ricostruito');
            
            % Area Errore
            fill(ax, [x_axis, fliplr(x_axis)], [orig_sig, fliplr(reco_sig)], 'r', ...
                 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'DisplayName', 'Errore (Anomalia)');
            
            title(ax, sens_names{c}, 'FontWeight', 'bold', 'FontSize', 10);
            ylim(ax, y_lims);
            xlim(ax, [1 length(x_axis)]);
            
            % Abbellimenti specifici
            if c == 1
                ylabel(ax, 'Ampiezza Normalizzata', 'FontWeight', 'bold');
            end
            if c == 4
                legend(ax, 'Location', 'northeast');
            end
        end
        
        % Aggiorniamo il titolo dinamico superiore nel pannello
        h_title = findobj(get(ax_ae_signal(1), 'Parent'), 'Tag', 'AE_Title_Lbl');
        if ~isempty(h_title)
            set(h_title, 'String', sprintf('Analisi Run: %s (Accuratezza: %.1f%%) - Originale vs Ricostruito', ...
                datestr(AE_Results(idx).DateNum, 'dd/mm/yy HH:MM'), AE_Results(idx).MSE));
        end
    end
    % --- FUNZIONE DI REGIA PER IL REDRAW DELLA PSD ---
    function refresh_psd_view(~, ~)
        % Pulizia profonda dell'asse per evitare conflitti tra viste 2D e 3D
        if isgraphics(ax_psd)
            cla(ax_psd, 'reset'); 
            hold(ax_psd, 'on');
            grid(ax_psd, 'on');
        end

        % Sceglie quale funzione di plotting chiamare
        if strcmp(PSD_Mode, '2D')
            update_psd();
        else
            update_psd_3d();
        end
    end






    function export_peak_report(~, ~)
        % 1. Chiedi all'utente dove salvare
        folder_name = uigetdir(pwd, 'Seleziona la cartella dove salvare i grafici del report');
        if folder_name == 0, return; end % Utente ha annullato
        
        % 2. Crea una sottocartella specifica per questo difetto
        export_dir = fullfile(folder_name, sprintf('Report_PK_%s', Defect.ID_PK));
        if ~exist(export_dir, 'dir'), mkdir(export_dir); end
        
        wb_exp = waitbar(0, 'Avvio esportazione grafici in corso...');
        
        % =================================================================
        % EXTRAZIONE DATI PER L'EXECUTIVE SUMMARY (IPI E RUN MASSIMA)
        % =================================================================
        waitbar(0.05, wb_exp, 'Estrazione dati di riepilogo e IPI...');
        
        % Leggi IPI dalla UI e pulisci eventuali tag HTML
        h_ipi = findobj(f_stat, 'Tag', 'IPI_Label');
        ipi_score = 'N/A';
        if ~isempty(h_ipi)
            ipi_score = regexprep(get(h_ipi, 'String'), '<[^>]*>', ''); % Rimuove tag HTML
        end
        
        h_ipi_det = findobj(pnl_ctrl, 'Tag', 'IPI_Dettaglio');
        ipi_dettaglio = 'N/A';
        if ~isempty(h_ipi_det)
            ipi_dettaglio = strrep(get(h_ipi_det, 'String'), '\', '\\'); % Protegge backslash per LaTeX
        end
        
        % Trova la corsa con il picco massimo
        [max_amp, max_idx] = max([RawDataStore.Amp]);
        run_max = RawDataStore(max_idx);
        date_max_str = datestr(run_max.Date, 'dd/mm/yyyy HH:MM');
        
        % Creazione Grafico 6 Segnali (Invisibile)
        waitbar(0.08, wb_exp, 'Generazione grafico dei 6 segnali (Run Massima)...');
        f_sig = figure('Visible', 'off', 'Position', [100, 100, 1000, 700], 'Color', 'w');
        
        % Determina il laterale dominante per la run massima
        rms_lat_dx = 0; rms_lat_sx = 0;
        if isfield(run_max.Signals, 'right_sensor_front_lat') && ~isempty(run_max.Signals.right_sensor_front_lat)
            rms_lat_dx = rms(double(run_max.Signals.right_sensor_front_lat)); 
        end
        if isfield(run_max.Signals, 'left_sensor_front_lat') && ~isempty(run_max.Signals.left_sensor_front_lat)
            rms_lat_sx = rms(double(run_max.Signals.left_sensor_front_lat)); 
        end
        
        if rms_lat_sx > rms_lat_dx
            l_f = 'left_sensor_front_lat'; l_r = 'left_sensor_rear_lat'; lat_tit = 'Lat SX';
        else
            l_f = 'right_sensor_front_lat'; l_r = 'right_sensor_rear_lat'; lat_tit = 'Lat DX';
        end
        
        sig_fields = {'left_sensor_front', 'left_sensor_rear', 'right_sensor_front', 'right_sensor_rear', l_f, l_r};
        sig_titles = {'Verticale SX (Front)', 'Verticale SX (Rear)', 'Verticale DX (Front)', 'Verticale DX (Rear)', [lat_tit ' (Front)'], [lat_tit ' (Rear)']};
        
        for s_idx = 1:6
            ax_s = subplot(3, 2, s_idx, 'Parent', f_sig);
            hold(ax_s, 'on'); grid(ax_s, 'on');
            if isfield(run_max.Signals, sig_fields{s_idx}) && ~isempty(run_max.Signals.(sig_fields{s_idx}))
                plot(ax_s, run_max.Axis, run_max.Signals.(sig_fields{s_idx}), 'Color', [0 0.4 0.8], 'LineWidth', 1.2);
                xline(ax_s, 0, 'r--', 'LineWidth', 1);
                xlabel(ax_s, 'Posizione [m]'); ylabel(ax_s, 'm/s^2');
            else
                text(ax_s, 0.5, 0.5, 'Nessun Dato', 'HorizontalAlignment', 'center');
            end
            title(ax_s, sig_titles{s_idx}, 'FontWeight', 'bold');
        end
        sgtitle(f_sig, sprintf('Firma Accelerometrica - Run Massima: %s (Picco: %.1f m/s^2)', date_max_str, max_amp), 'FontWeight', 'bold', 'FontSize', 14);
        
        exportgraphics(f_sig, fullfile(export_dir, '0_Max_Run_Signals.png'), 'Resolution', 300);
        close(f_sig);
        
        % =================================================================
        % ESPORTAZIONE GRAFICI AUTOENCODER (IA)
        % =================================================================
        waitbar(0.10, wb_exp, 'Esportazione grafici Intelligenza Artificiale...');
        has_ae = false;
        try
            if ~isempty(get(ax_ae_trend, 'Children'))
                exportgraphics(ax_ae_trend, fullfile(export_dir, '0_AE_Trend.png'), 'Resolution', 300);
                eexportgraphics(get(ax_ae_signal(1), 'Parent'), fullfile(export_dir, '0_AE_Signal.png'), 'Resolution', 300);
                has_ae = true;
            end
        catch
        end


        % =================================================================
        % ESPORTAZIONE GRAFICI PCA
        % =================================================================
        waitbar(0.12, wb_exp, 'Esportazione grafici PCA...');
        has_pca = false;
        try
            if ~isempty(get(ax_pca_anom, 'Children'))
                exportgraphics(ax_pca_anom, fullfile(export_dir, '0_PCA_Anom.png'), 'Resolution', 300);
                exportgraphics(ax_pca_scree, fullfile(export_dir, '0_PCA_Scree.png'), 'Resolution', 300);
                exportgraphics(ax_pca_mani, fullfile(export_dir, '0_PCA_Mani.png'), 'Resolution', 300);
                exportgraphics(ax_pca_sig, fullfile(export_dir, '0_PCA_Sig.png'), 'Resolution', 300);
                has_pca = true;
            end
        catch
        end

        % =================================================================
        % ESPORTAZIONE GRAFICI STANDARD (CON PRE-SCAN ADATTIVO PER RAGGRUPPAMENTO)
        % =================================================================
        ragg_idx = [1, 2];
        ragg_nomi = {'1_Singole', '2_Giornaliera'};
        
        nomi_profili = {'Verticale_SX', 'Verticale_DX', 'Laterale_DX', 'Laterale_SX'};
        titoli_profili = {'Verticale Sinistro', 'Verticale Destro', 'Laterale Destro', 'Laterale Sinistro'};
        
        nomi_psd = {'Vert_SX_Front', 'Vert_SX_Rear', 'Vert_DX_Front', 'Vert_DX_Rear', 'Lat_DX_Front', 'Lat_DX_Rear', 'Lat_SX_Front', 'Lat_SX_Rear'};
        titoli_psd = {'Vert. SX Front', 'Vert. SX Rear', 'Vert. DX Front', 'Vert. DX Rear', 'Lat. DX Front', 'Lat. DX Rear', 'Lat. SX Front', 'Lat. SX Rear'};
        
        n_tot_steps = length(ragg_idx) * (1 + 4 + 8 + 1); 
        curr_step = 0;
        
        for r = 1:length(ragg_idx)
            prefix = ragg_nomi{r};
            nome_ragg = strrep(prefix, '_', ' '); 
            
            % 1. Imposta il raggruppamento (Singole, Giornaliere, Settimanali)
            set(pop_grouping, 'Value', ragg_idx(r));
            on_ctrl_change(pop_grouping, []); 
            drawnow; pause(0.5); 
            
            curr_step = curr_step + 1;
            waitbar(0.15 + (curr_step/n_tot_steps)*0.75, wb_exp, sprintf('%s: Calcolo scale unificate per %s...', nome_ragg, nome_ragg));
            
            % --- PRE-SCAN: CALCOLO LIMITI DI SCALA PER QUESTO SPECIFICO RAGGRUPPAMENTO ---
            PSD_Mode = '3D';
            loc_max_vert_prof = 0.1; loc_max_lat_prof = 0.1;
            loc_max_vert_psd  = 0.1; loc_max_lat_psd  = 0.1;
            
            % Scan Profili (1-2 = Vert, 3-4 = Lat)
            for i_temp = 1:4
                set(pop_sensor, 'Value', i_temp); on_ctrl_change(pop_sensor, []); drawnow;
                z_max_raw = max(ax3.ZLim(2), max(ax3.Children(end).ZData(:), [], 'omitnan'));
                if i_temp <= 2
                    loc_max_vert_prof = max(loc_max_vert_prof, z_max_raw * 1.10);
                else
                    loc_max_lat_prof = max(loc_max_lat_prof, z_max_raw * 1.10);
                end
            end
            
            % Scan PSD (1-4 = Vert, 5-8 = Lat)
            for i_temp = 1:8
                set(pop_psd_sens, 'Value', i_temp); refresh_psd_view([], []); drawnow;
                if i_temp <= 4
                    loc_max_vert_psd = max(loc_max_vert_psd, ax_psd.ZLim(2));
                else
                    loc_max_lat_psd = max(loc_max_lat_psd, ax_psd.ZLim(2));
                end
            end
            
            % --- ESPORTAZIONE PROFILI (CON SCALA BLOCCATA SUL GRUPPO CORRENTE) ---
            for idx_prof = 1:4
                curr_step = curr_step + 1;
                waitbar(0.15 + (curr_step/n_tot_steps)*0.75, wb_exp, sprintf('%s: Profilo %d di 4...', nome_ragg, idx_prof));
                set(pop_sensor, 'Value', idx_prof);
                on_ctrl_change(pop_sensor, []); 
                drawnow; pause(0.2);
                
                % Applica scala bloccata
                if idx_prof <= 2
                    zlim(ax3, [0, loc_max_vert_prof]);
                    try clim(ax3, [0, loc_max_vert_prof]); catch, caxis(ax3, [0, loc_max_vert_prof]); end
                else
                    zlim(ax3, [0, loc_max_lat_prof]);
                    try clim(ax3, [0, loc_max_lat_prof]); catch, caxis(ax3, [0, loc_max_lat_prof]); end
                end
                
                exportgraphics(ax3, fullfile(export_dir, sprintf('%s_A_Profilo_%s.png', prefix, nomi_profili{idx_prof})), 'Resolution', 300);
            end
            
            % --- ESPORTAZIONE PSD (CON SCALA BLOCCATA SUL GRUPPO CORRENTE) ---
            for idx_psd = 1:8
                curr_step = curr_step + 1;
                waitbar(0.15 + (curr_step/n_tot_steps)*0.75, wb_exp, sprintf('%s: PSD %d di 8...', nome_ragg, idx_psd));
                set(pop_psd_sens, 'Value', idx_psd);
                refresh_psd_view([], []);
                drawnow; pause(0.2);
                
                % Applica scala bloccata
                if idx_psd <= 4
                    zlim(ax_psd, [0, loc_max_vert_psd]);
                    try clim(ax_psd, [0, loc_max_vert_psd]); catch, caxis(ax_psd, [0, loc_max_vert_psd]); end
                else
                    zlim(ax_psd, [0, loc_max_lat_psd]);
                    try clim(ax_psd, [0, loc_max_lat_psd]); catch, caxis(ax_psd, [0, loc_max_lat_psd]); end
                end

                exportgraphics(ax_psd, fullfile(export_dir, sprintf('%s_B_PSD_%d_%s.png', prefix, idx_psd, nomi_psd{idx_psd})), 'Resolution', 300);
            end
            
            % --- ESPORTAZIONE RIEPILOGHI ---
            curr_step = curr_step + 1;
            waitbar(0.15 + (curr_step/n_tot_steps)*0.75, wb_exp, sprintf('%s: Salvataggio riepiloghi...', nome_ragg));
            exportgraphics(ax_3x3, fullfile(export_dir, sprintf('%s_C_Matrice3x3.png', prefix)), 'Resolution', 300);
            exportgraphics(ax_lat, fullfile(export_dir, sprintf('%s_D_RatioLat.png', prefix)), 'Resolution', 300);
            exportgraphics(ax_lam, fullfile(export_dir, sprintf('%s_E_Lambda.png', prefix)), 'Resolution', 300);
        end
        
        % =====================================================================
        % GENERAZIONE AUTOMATICA DEL FILE LATEX E DEL PDF (MiKTeX)
        % =====================================================================
        waitbar(0.92, wb_exp, 'Generazione del PDF in LaTeX in corso...');
        
        tex_filename = fullfile(export_dir, sprintf('Report_%s.tex', Defect.ID_PK));
        fid = fopen(tex_filename, 'w');
        
        fprintf(fid, '\\documentclass[11pt]{article}\n');
        fprintf(fid, '\\usepackage[utf8]{inputenc}\n');
        fprintf(fid, '\\usepackage{graphicx}\n');
        fprintf(fid, '\\usepackage[a4paper, margin=1.5cm]{geometry}\n');
        fprintf(fid, '\\usepackage{float}\n');
        fprintf(fid, '\\usepackage{subcaption}\n');
        fprintf(fid, '\\usepackage{xcolor}\n');


        fprintf(fid, '\\usepackage{amsmath}\n');
        fprintf(fid, '\\usepackage{amssymb}\n');
        safe_id = strrep(Defect.ID_PK, '_', '\_');
        fprintf(fid, '\\title{Report Diagnostico Difetto: \\textbf{%s}}\n', safe_id);
        fprintf(fid, '\\author{Inspector V10 - Analisi Automatica}\n');
        fprintf(fid, '\\date{\\today}\n\n');

        fprintf(fid, '\\begin{document}\n');
        fprintf(fid, '\\maketitle\n\n');
        
        % --- SEZIONE 1: EXECUTIVE SUMMARY ---
        fprintf(fid, '\\section*{Executive Summary}\n');
        fprintf(fid, '\\begin{itemize}\n');
        fprintf(fid, '\\item \\textbf{Indice di Priorità Ispezione (IPI):} {\\large \\textbf{%s}}\n', ipi_score);
        fprintf(fid, '\\item \\textbf{Dettaglio Calcolo:} %s\n', ipi_dettaglio);
        fprintf(fid, '\\item \\textbf{Massima Severità Storica:} %.1f m/s$^2$ (Registrata il %s)\n', max_amp, date_max_str);
        fprintf(fid, '\\end{itemize}\n\n');
        
        fprintf(fid, 'La seguente figura illustra i 6 canali cinematici principali estratti durante il passaggio di massima severità. Questo permette di valutare visivamente la distribuzione delle forze sul carrello nel momento più critico.\n\n');
        
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        fprintf(fid, '\\includegraphics[width=\\textwidth]{0_Max_Run_Signals.png}\n');
        fprintf(fid, '\\caption{Segnali cinematici del passaggio a massima severità (Picco %.1f m/s$^2$). Vengono mostrati i 4 punti verticali e l''asse laterale dominante per identificare asimmetrie o colpi netti.}\n', max_amp);
        fprintf(fid, '\\end{figure}\n\n');
        fprintf(fid, '\\clearpage\n\n');

        % --- SEZIONE 1.5: AUTOENCODER (SE PRESENTE) ---
        if has_ae
            fprintf(fid, '\\section*{Analisi Predittiva con IA (Autoencoder)}\n');
            fprintf(fid, 'L''Autoencoder valuta lo stato di salute dell''infrastruttura ricostruendo i segnali cinematici mediante una rete neurale non lineare. Un calo nell''accuratezza di ricostruzione indica un''anomalia o un degrado rispetto alla firma appresa dal modello.\n\n');
            
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            fprintf(fid, '\\includegraphics[width=0.9\\textwidth]{0_AE_Trend.png}\n');
            fprintf(fid, '\\caption{Curva di degradazione nel tempo (Trend dell''Accuratezza). Valori percentuali decrescenti indicano un marcato peggioramento delle condizioni cinematiche.}\n');
            fprintf(fid, '\\end{figure}\n\n');
            
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            fprintf(fid, '\\includegraphics[width=0.9\\textwidth]{0_AE_Signal.png}\n');
            fprintf(fid, '\\caption{Confronto tra la firma accelerometrica originale e quella attesa (ricostruita) dall''IA per l''ultimo passaggio registrato. L''area rossa evidenziata rappresenta il residuo di anomalia.}\n');
            fprintf(fid, '\\end{figure}\n\n');
            fprintf(fid, '\\clearpage\n\n');
        end
        

       % --- SEZIONE 1.6: PCA (SE PRESENTE) ---
        if has_pca
            fprintf(fid, '\\section*{Analisi delle Componenti Principali (PCA)}\n');
            fprintf(fid, 'L''analisi PCA ($k=2$ preset) estrae la firma cinematica principale e valuta l''anomalia attraverso l''errore quadratico medio (RMSE) della ricostruzione.\\\\\n\n');
            
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{0_PCA_Anom.png}\n\\caption{Anomaly Score (RMSE)}\\end{subfigure}\\hfill\n');
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{0_PCA_Scree.png}\n\\caption{Scree Plot (Varianza)}\\end{subfigure}\\\\[0.4cm]\n');
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{0_PCA_Mani.png}\n\\caption{Manifold PC1-PC2}\\end{subfigure}\\hfill\n');
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{0_PCA_Sig.png}\n\\caption{Firma Originale vs Ricostruita}\\end{subfigure}\n');
            fprintf(fid, '\\caption{Risultati dell''analisi PCA sul difetto per $k=2$.}\n');
            fprintf(fid, '\\end{figure}\n\n');
            
            % Dettagli matematici dei grafici per facilitare la lettura ingegneristica
            fprintf(fid, '\\textbf{Analisi Matematica e Guida alla Lettura:}\n');
            fprintf(fid, '\\begin{itemize}\n');
            
            fprintf(fid, '  \\item \\textbf{(a) Anomaly Score (RMSE):} Valuta l''errore quadratico medio di ricostruzione. Data la matrice dei dati standardizzata $\\mathbf{Z} \\in \\mathbb{R}^{N \\times M}$ (con $N$ passaggi e $M$ feature spaziali) e la sua ricostruzione troncata $\\mathbf{\\hat{Z}}^{(k)} = \\mathbf{S}_{k}\\mathbf{C}_{k}^{T}$, il residuo è $\\mathbf{R} = \\mathbf{Z} - \\mathbf{\\hat{Z}}^{(k)}$. L''Anomaly Score per l''$i$-esimo passaggio è calcolato come:\n');
            fprintf(fid, '  \\[ RMSE_i = \\sqrt{\\frac{1}{M} \\sum_{j=1}^{M} R_{i,j}^2} \\]\n');
            fprintf(fid, '  Un trend in crescita indica una mutazione cinematica non spiegabile dalla base storica. La soglia statistica di allarme è tracciata a $\\mu_{RMSE} + 2\\sigma_{RMSE}$.\n\n');
            
            fprintf(fid, '  \\item \\textbf{(b) Scree Plot (Varianza):} Rappresenta la percentuale di varianza spiegata $EV_m$ dall''$m$-esima componente principale, calcolata dagli autovalori $\\lambda$ della matrice di covarianza di $\\mathbf{Z}$:\n');
            fprintf(fid, '  \\[ EV_m [\\%%] = \\frac{\\lambda_m}{\\sum_{j} \\lambda_j} \\times 100 \\]\n');
            fprintf(fid, '  Il grafico mostra la curva cumulativa per $k=2$. Una varianza spiegata bassa indica un difetto dal comportamento caotico, instabile o fortemente multi-modale.\n\n');
            
            fprintf(fid, '  \\item \\textbf{(c) Manifold PC1-PC2:} Proiezione delle firme cinematiche nello spazio latente 2D definito dai primi due autovettori ortogonali $\\mathbf{v}_1$ e $\\mathbf{v}_2$. Le coordinate (PCA scores) sono le proiezioni scalari:\n');
            fprintf(fid, '  \\[ s_{i,1} = \\mathbf{Z}_i \\cdot \\mathbf{v}_1 \\quad \\text{e} \\quad s_{i,2} = \\mathbf{Z}_i \\cdot \\mathbf{v}_2 \\]\n');
            fprintf(fid, '  Punti contigui indicano urti cinematicamente simili. Una chiara migrazione temporale dei punti all''interno di questo piano vettoriale denota una progressiva evoluzione geometrica del difetto sul binario.\n\n');
            
            fprintf(fid, '  \\item \\textbf{(d) Firma Originale vs Ricostruita:} Mostra l''evento con il massimo $RMSE$ riportato nelle unità fisiche originali $[m/s^2]$. La trasformazione inversa (destandardizzazione) avviene applicando la media $\\mu_c$ e la deviazione standard $\\sigma_c$ pre-calcolate per ogni specifico canale $c$:\n');
            fprintf(fid, '  \\[ \\hat{X}_{i,c} = \\hat{Z}_{i,c} \\cdot \\sigma_c + \\mu_c \\]\n');
            fprintf(fid, '  Le aree di maggior distacco tra l''inviluppo originario misurato e la proiezione lineare $\\mathbf{\\hat{X}}$ evidenziano asimmetrie anomale non conformi allo storico del difetto.\n');
            
            fprintf(fid, '\\end{itemize}\n\n');
            
            fprintf(fid, '\\clearpage\n\n');
        end
        % --- SEZIONE 2: ANALISI EVOLUTIVA ---
        titoli_sez = {'Analisi Singole Corse', 'Media Giornaliera'};
        
        for r = 1:length(ragg_idx)
            prefix = ragg_nomi{r};
            fprintf(fid, '\\section{%s}\n', titoli_sez{r});
            
            % --- Indicatori Globali (INCOLONNATI GRANDI) ---
            fprintf(fid, '\\subsection*{Indicatori Diagnostici Evolutivi}\n');
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            fprintf(fid, '\\begin{subfigure}[b]{0.6\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s_C_Matrice3x3.png}\n\\caption{Matrice 3x3 Simmetria}\\end{subfigure}\\\\[0.3cm]\n', prefix);
            fprintf(fid, '\\begin{subfigure}[b]{0.6\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s_D_RatioLat.png}\n\\caption{Rapporto Laterale/Verticale}\\end{subfigure}\\\\[0.3cm]\n', prefix);
            fprintf(fid, '\\begin{subfigure}[b]{0.6\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s_E_Lambda.png}\n\\caption{Evoluzione Lunghezza d''Onda}\\end{subfigure}\n', prefix);
            fprintf(fid, '\\caption{Indicatori globali per la finestra: %s}\n', titoli_sez{r});
            fprintf(fid, '\\end{figure}\n\n');
            
            fprintf(fid, '\\clearpage\n\n'); % SALTO PAGINA PER I WATERFALL
            
            % --- Profili Spaziali (Con Subcaption) ---
            fprintf(fid, '\\subsection*{Evoluzione Profilo Spaziale 3D (Max RMS)}\n');
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            for idx_prof = 1:4
                fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\n');
                fprintf(fid, '\\includegraphics[width=\\textwidth]{%s_A_Profilo_%s.png}\n', prefix, nomi_profili{idx_prof});
                fprintf(fid, '\\caption{Waterfall %s}\n', titoli_profili{idx_prof});
                fprintf(fid, '\\end{subfigure}\n');
                if mod(idx_prof, 2) == 1, fprintf(fid, '\\hfill\n');
                elseif idx_prof == 2, fprintf(fid, '\n\n\\vspace{0.4cm}\n\n'); end
            end
            fprintf(fid, '\\caption{Evoluzione della forma d''onda spaziale per i 4 gruppi sensori - %s. (Nota: Scale colori e asse Z uniformati per questo raggruppamento)}\n', titoli_sez{r});
            fprintf(fid, '\\end{figure}\n\n');
            fprintf(fid, '\\clearpage\n\n'); 
            
            % --- Analisi PSD Verticali (Con Subcaption) ---
            fprintf(fid, '\\subsection*{Evoluzione Spettrale (PSD 3D) - Sensori Verticali}\n');
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            for idx_psd = 1:4
                fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\n');
                fprintf(fid, '\\includegraphics[width=\\textwidth]{%s_B_PSD_%d_%s.png}\n', prefix, idx_psd, nomi_psd{idx_psd});
                fprintf(fid, '\\caption{PSD: %s}\n', titoli_psd{idx_psd});
                fprintf(fid, '\\end{subfigure}\n');
                if mod(idx_psd, 2) == 1, fprintf(fid, '\\hfill\n');
                elseif idx_psd == 2, fprintf(fid, '\n\n\\vspace{0.4cm}\n\n'); end
            end
            psd_win_val = str2double(get(edit_psd_win, 'String')); if isnan(psd_win_val), psd_win_val = 10.0; end
            fprintf(fid, '\\caption{Contenuto in frequenza spaziale (Power Spectral Density) per i sensori verticali. Finestra di analisi: %.0f m. (Nota: Scale colori e asse Z uniformati per questo raggruppamento)}\n', psd_win_val);
            fprintf(fid, '\\end{figure}\n\n');
            
            % --- Analisi PSD Laterali (Con Subcaption) ---
            fprintf(fid, '\\subsection*{Evoluzione Spettrale (PSD 3D) - Sensori Laterali}\n');
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            for idx_psd = 5:8
                fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\n');
                fprintf(fid, '\\includegraphics[width=\\textwidth]{%s_B_PSD_%d_%s.png}\n', prefix, idx_psd, nomi_psd{idx_psd});
                fprintf(fid, '\\caption{PSD: %s}\n', titoli_psd{idx_psd});
                fprintf(fid, '\\end{subfigure}\n');
                if mod(idx_psd, 2) == 1, fprintf(fid, '\\hfill\n');
                elseif idx_psd == 6, fprintf(fid, '\n\n\\vspace{0.4cm}\n\n'); end
            end
            fprintf(fid, '\\caption{Contenuto in frequenza spaziale (Power Spectral Density) per i sensori laterali. Finestra di analisi: %.0f m. (Nota: Scale colori e asse Z uniformati per questo raggruppamento)}\n', psd_win_val);
            fprintf(fid, '\\end{figure}\n\n');
            
            fprintf(fid, '\\clearpage\n\n');
        end
        
        fprintf(fid, '\\end{document}\n');
        fclose(fid);
        
        % =====================================================================
        % COMPILAZIONE DEL PDF
        % =====================================================================
        waitbar(1, wb_exp, 'Compilazione PDF...');
        old_dir = cd(export_dir); 
        
        try
            [status, cmdout] = system(sprintf('pdflatex -interaction=nonstopmode "Report_%s.tex"', Defect.ID_PK));
            cd(old_dir); 
            
            if status == 0
                close(wb_exp);
                msgbox(sprintf('Report PDF generato con successo in:\n%s', export_dir), 'PDF Pronto');
                try winopen(fullfile(export_dir, sprintf('Report_%s.pdf', Defect.ID_PK))); catch, end
            else
                close(wb_exp);
                errordlg('Immagini esportate, ma la compilazione LaTeX ha restituito un errore. Controlla la Command Window.', 'Errore Compilazione');
                disp('--- ERRORE LATEX ---'); disp(cmdout); 
            end
            
        catch ME
            cd(old_dir);
            close(wb_exp);
            errordlg(['Impossibile lanciare pdflatex. Dettagli: ', ME.message]);
        end
    end


   function update_IPI_Score()
    % Recupero configurazione globale
    C = h.CFG; 
    
    if n_days < C.IPI_MIN_DAYS
        score_str = sprintf('N/A (Pochi Giorni: %d/%d)', n_days, C.IPI_MIN_DAYS);
        col_semaforo = [0.7 0.7 0.7]; 
        ipi_final = 0;
        str_dettaglio = ['Dati insufficienti per calcolo IPI (min ', num2str(C.IPI_MIN_DAYS), ' giorni)'];
        S_trend = 0; S_absolute = 0; Bonus_lat = 0; Bonus_ia = 0; inc_perc = 0; Bonus_pca = 0;
    else
        % --- RAGGRUPPAMENTO GIORNALIERO ---
        Severity_Daily = zeros(n_days, 1);
        Ratio_LV_Daily = zeros(n_days, 1);
        for d = 1:n_days
            mask = (days_floor == unique_days(d));
            Severity_Daily(d) = mean(Severity(mask), 'omitnan');
            Ratio_LV_Daily(d) = mean(Ratio_LV(mask), 'omitnan');
        end
        
        S_trend = 0; S_absolute = 0; inc_perc = 0; Bonus_lat = 0; rms_recent = NaN;
        history_span = unique_days(end) - unique_days(1);
        
        if history_span >= C.IPI_MIN_HISTORY_DAYS
            cutoff_day  = unique_days(end) - C.IPI_RECENT_DAYS;
            mask_recent = unique_days >  cutoff_day;
            mask_base   = unique_days <= cutoff_day;
            
            if any(mask_recent) && any(mask_base)
                rms_base   = mean(Severity_Daily(mask_base),   'omitnan');
                rms_recent = mean(Severity_Daily(mask_recent), 'omitnan');
                
                % 1. VOTO BASE: TREND (Max 50 Punti)
                if rms_base > 0
                    inc_perc = ((rms_recent - rms_base) / rms_base) * 100;
                    S_trend = min(50, max(0, inc_perc * (50 / C.IPI_TREND_SENS)));
                end
                
                % 2. VOTO BASE: SEVERITÀ ASSOLUTA (Max 50 Punti)
                if rms_recent < C.IPI_SEV_THR_LOW
                    S_absolute = 0;
                elseif rms_recent > C.IPI_SEV_THR_HIGH
                    S_absolute = 50;
                else
                    S_absolute = 50 * (rms_recent - C.IPI_SEV_THR_LOW) / (C.IPI_SEV_THR_HIGH - C.IPI_SEV_THR_LOW);
                end
                
                % 3. AGGRAVANTE: LATERALE
                recent_ratio_lv = mean(Ratio_LV_Daily(mask_recent), 'omitnan');
                Bonus_lat = min(C.IPI_LAT_BONUS, max(0, (recent_ratio_lv / C.IPI_LAT_THRESH) * C.IPI_LAT_BONUS));
            end
        end
        
        % 4. AGGRAVANTE: IA
        Bonus_ia = 0;
        if ~isempty(AE_Net) && ~isempty(AE_mu) && ~isempty(AE_sigma)
            AE_Model_Local = struct('net', AE_Net, 'mu', AE_mu, 'sigma', AE_sigma, ...
                                    'v_ref', AE_v_ref, 'loaded', true);
            [Bonus_ia, ~] = compute_ae_bonus_for_defect(Defect, AE_Model_Local, h.CFG);
        end
        
        % 5. AGGRAVANTE: PCA
        [Bonus_pca, ~] = compute_pca_bonus_for_defect(Defect, h.CFG);
        
        % 6. CALCOLO FINALE BILANCIATO
        ipi_raw = S_absolute + S_trend + Bonus_lat + Bonus_pca + Bonus_ia;
        ipi_final = round(min(100, max(0, ipi_raw))); 
        
        if isnan(rms_recent)
            str_dettaglio = sprintf('Selezionato: %s | RMS Recente: N/D (storia < %d gg)', Defect.ID_PK, C.IPI_MIN_HISTORY_DAYS);
        else
            str_dettaglio = sprintf('Selezionato: %s | RMS Recente: %.1f m/s^2', Defect.ID_PK, rms_recent);
        end
        
        if ipi_final >= 75, col_semaforo = [0.8 0 0];     
        elseif ipi_final >= 50, col_semaforo = [1 0.5 0];     
        elseif ipi_final >= 25, col_semaforo = [0.9 0.8 0];   
        else, col_semaforo = [0 0.6 0]; end
        score_str = sprintf('%d / 100', ipi_final);
    end

    % --- AGGIORNAMENTO TESTI UI INTERFACCIA ---
    h_lbl = findobj(f_stat, 'Tag', 'IPI_Label');
    if isempty(h_lbl)
        uicontrol('Parent', f_stat, 'Style', 'text', 'String', 'RISCHIO DEGRADO (IPI):', ...
            'Units', 'normalized', 'Position', [0.45 0.95 0.15 0.04], ...
            'BackgroundColor', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
        h_lbl = uicontrol('Parent', f_stat, 'Style', 'text', 'Tag', 'IPI_Label', ...
            'Units', 'normalized', 'Position', [0.6 0.95 0.08 0.04], ...
            'FontWeight', 'bold', 'FontSize', 12, 'ForegroundColor', 'w');
    end
    set(h_lbl, 'String', score_str, 'BackgroundColor', col_semaforo);
    
    h_coeff = findobj(f_stat, 'Tag', 'IPI_Coeff_Label');
    if isempty(h_coeff)
        h_coeff = uicontrol('Parent', f_stat, 'Style', 'text', 'Tag', 'IPI_Coeff_Label', ...
            'Units', 'normalized', 'Position', [0.05 0.95 0.4 0.04], ... 
            'BackgroundColor', 'w', 'FontSize', 9, 'FontAngle', 'italic', ...
            'HorizontalAlignment', 'center', 'ForegroundColor', [0.3 0.3 0.3]);
    end
    
    if ipi_final > 0
        coeff_str = sprintf('Assoluto: %.1f/50 | Trend: %.1f/50 | Lat(+%.1f) PCA(+%.1f) IA(+%.1f) = Tot: %.1f', ...
            S_absolute, S_trend, Bonus_lat, Bonus_pca, Bonus_ia, ipi_raw);
    else
        coeff_str = 'In attesa di dati sufficienti (min 10 giorni)...';
    end
    set(h_coeff, 'String', coeff_str);
    
    h_dettaglio = findobj(pnl_ctrl, 'Tag', 'IPI_Dettaglio');
    if isempty(h_dettaglio)
        h_dettaglio = uicontrol('Parent', pnl_ctrl, 'Style', 'text', 'Tag', 'IPI_Dettaglio', ...
            'Units', 'normalized', 'Position', [0.01 0.05 0.98 0.20], ...
            'BackgroundColor', 'w', 'ForegroundColor', [0.3 0.3 0.3], ...
            'HorizontalAlignment', 'left', 'FontAngle', 'italic');
    end
    set(h_dettaglio, 'String', str_dettaglio);
end




end




     
    % =========================================================================
% NUOVA FUNZIONE: REPORT GLOBALE PCA (CLASSIFICAZIONE DIFETTI)
% =========================================================================

% 
% function generate_pca_population_report(DB)
%     if isempty(DB), msgbox('Database vuoto.'); return; end
% 
%     wb = waitbar(0, 'Analisi PCA su intera popolazione...');
%     n_db = length(DB);
% 
%     % Strutture per raccogliere i risultati
%     SummaryData = struct('ID', {}, 'Pos', {}, 'Amp', {}, 'Mode', {}, 'Conf', {});
% 
% 
% % --- PARAMETRI GEOMETRICI ---
%     WHEELBASE = 2.1500; % Distanza tra i sensori (Passo Carrello)
% 
%     % Definizione Sensori (Ordine fisso per la PCA)
%     sens_list = {'left_sensor_front', 'left_sensor_rear', ...
%                  'right_sensor_front', 'right_sensor_rear', ...
%                  'right_sensor_front_lat', 'right_sensor_rear_lat',...
%                  'left_sensor_front_lat', 'left_sensor_rear_lat'};
% 
%     for i = 1:n_db
%         waitbar(i/n_db, wb);
%         Defect = DB(i);
% 
%         % 1. Costruzione Matrice Storia (Passaggi x 6 Sensori)
%         X = [];
%         for k = 1:length(Defect.History)
%             run = Defect.History(k);
% 
%             % Verifica che ci siano i dati e l'asse spaziale relativo
%             if isfield(run.Data, 'Filt') && isfield(run.Data, 'RelativeAxis')
% 
%                 % Asse spaziale centrato sul picco (0 = impatto frontale)
%                 ax_space = run.Data.RelativeAxis;
% 
%                 row = zeros(1, 6); 
%                 has_data = true;
% 
%                 for s = 1:6
%                     s_name = sens_list{s};
%                     if isfield(run.Data.Filt, s_name)
%                         % Segnale FILTRATO (oscillante con segno +/-)
%                         sig = run.Data.Filt.(s_name);
% 
%                         % --- LOGICA SINCRONA (SHIFT) ---
%                         if contains(s_name, 'front')
%                             target_x = 0;       % Frontale: Leggiamo all'impatto
%                         else
%                             target_x = -WHEELBASE; % Posteriore: Leggiamo dove si trovava (-2.15m)
%                         end
% 
%                         % --- FIX: PROTEZIONE LUNGHEZZA PER INTERP1 ---
%                         val = 0; % Valore di default se fallisce
%                         if ~isempty(sig) && ~isempty(ax_space) && length(sig) > 1 && length(ax_space) > 1
%                             % Sincronizza le lunghezze al valore minimo
%                             L_min = min(length(sig), length(ax_space));
%                             sig_clean = double(sig(1:L_min));
%                             ax_clean  = double(ax_space(1:L_min));
% 
%                             if length(ax_clean) >= 2
%                                 val = interp1(ax_clean, sig_clean, target_x, 'linear', NaN);
%                             end
%                         end
% 
%                         % Gestione casi limite (finestra troppo corta, o fuori range)
%                         if isnan(val), val = 0; end
% 
%                         row(s) = val;
%                     else
%                         has_data = false; 
%                     end
%                 end
% 
%                 if has_data, X = [X; row]; end
%             end
%         end
% 
%         % 2. Esecuzione PCA Singolo Difetto
%         defect_mode = "Dati Insuff.(n. passaggi < 3)"; 
%         defect_conf = 0;
% 
%         % Servono almeno 3 passaggi per una PCA sensata
%         if size(X, 1) >= 3
%             % Normalizzazione Z-Score (Importante per pesare i sensori ugualmente)
%             % Nota: X contiene valori positivi e negativi ora.
%             mu = mean(X); 
%             sig = std(X); 
%             sig(sig==0) = 1; % Evita divisione per zero
% 
%             X_std = (X - mu) ./ sig;
% 
%             try
%                 [coeffs, ~, latent] = pca(X_std);
%                 PC1 = coeffs(:, 1); % Primo Autovettore (Forma del modo)
% 
%                 variance_explained = 100 * latent(1) / sum(latent);
% 
%                 % 3. Classificazione Automatica (Usa la funzione helper basata sui segni)
%                 defect_mode = classify_defect_shape(PC1);
%                 defect_conf = variance_explained;
%             catch
%                 defect_mode = "Err Calc";
%             end
%         end
% 
%         % Salvataggio
%         SummaryData(i).ID = Defect.ID_PK;
%         SummaryData(i).Pos = Defect.Avg_Pos;
%         SummaryData(i).Amp = Defect.Max_Severity;
%         SummaryData(i).Mode = defect_mode;
%         SummaryData(i).Conf = defect_conf;
%     end
%     close(wb);
%     % --- CREAZIONE DASHBOARD ---
%     f_rep = figure('Name', 'Report Globale PCA: Classificazione Difetti', 'Color', 'w', 'Units', 'normalized', 'Position', [0.1 0.1 0.85 0.85]);
% 
%     % =====================================================================
%     % 1. AREA SUPERIORE: GRAFICI DI RIEPILOGO
%     % =====================================================================
% 
%     % GRAFICO A TORTA (TIPI DI DIFETTO)
%     ax_pie = subplot(2, 2, 1, 'Parent', f_rep);
%     all_modes = string({SummaryData.Mode}); 
%     mask_valid = ~ismember(all_modes, ["Dati Insuff.(n. run < 3)", "Err Calc", "N/A"]);
%     valid_modes = all_modes(mask_valid);
% 
%     if ~isempty(valid_modes)
%         C = categorical(valid_modes);
%         pie(ax_pie, C);
%         title(ax_pie, 'Distribuzione Tipologie Difetti');
%     else
%         text(ax_pie, 0.5, 0.5, 'Nessun dato classificabile', 'HorizontalAlignment', 'center');
%     end
% 
%     % MAPPA LINEA (Scatter Colorato per Tipo)
%     ax_map = subplot(2, 2, 2, 'Parent', f_rep); hold(ax_map, 'on'); grid(ax_map, 'on');
%     if ~isempty(valid_modes)
%         cats = categories(categorical(valid_modes));
%         colors = lines(length(cats));
%         for c = 1:length(cats)
%             current_type = string(cats{c});
%             idx = (all_modes == current_type);
%             if any(idx)
%                 scatter(ax_map, [SummaryData(idx).Pos], [SummaryData(idx).Amp], ...
%                     40, colors(c,:), 'filled', 'DisplayName', current_type);
%             end
%         end
%         legend(ax_map, 'Location', 'bestoutside');
%     end
%     xlabel(ax_map, 'Posizione PK [m]'); ylabel(ax_map, 'Severità Max [m/s^2]');
%     title(ax_map, 'Mappa Difetti per Tipologia');
% 
%     % =====================================================================
%     % 2. AREA INFERIORE: TABELLA DETTAGLI (SX) + GALLERIA VISIVA (DX)
%     % =====================================================================
% 
%     % --- A. Tabella Dettagli ---
%     pnl_tab = uipanel('Parent', f_rep, 'Position', [0.02 0.02 0.58 0.45], ...
%         'Title', 'Dettaglio Classificazione', 'BackgroundColor', 'w');
% 
%     col_names = {'ID Difetto', 'Posizione', 'Max Amp [m/s^2]', 'Movimento', 'Coerenza %'};
%     col_width = {100, 80, 80, 130, 80};
% 
%     tab_data = cell(n_db, 5);
%     for i=1:n_db
%         tab_data{i,1} = SummaryData(i).ID;
%         tab_data{i,2} = SummaryData(i).Pos;
%         tab_data{i,3} = SummaryData(i).Amp;
%         tab_data{i,4} = char(SummaryData(i).Mode);
%         tab_data{i,5} = sprintf('%.1f %%', SummaryData(i).Conf);
%     end
% 
%     uitable('Parent', pnl_tab, 'Data', tab_data, 'ColumnName', col_names, ...
%         'ColumnWidth', col_width, 'Units', 'normalized', ...
%         'Position', [0.02 0.05 0.96 0.90], 'RowName', [], 'FontSize', 9);
% 
%     % --- B. Galleria Visiva Movimenti (NUOVO) ---
%     pnl_gallery = uipanel('Parent', f_rep, 'Position', [0.61 0.02 0.38 0.45], ...
%         'Title', 'Legenda Visiva Movimenti', 'BackgroundColor', 'w');
% 
%     movements_to_draw = {'Sussulto', 'Beccheggio', 'Rollio', 'Sghembo', 'Colpo Lat. (Puro)', 'Serpeggio'};
% 
%     % Creiamo una griglia 2x3 di piccoli assi per gli schemi
%     for k = 1:6
%         % Calcolo posizione in griglia 2x3
%         row = ceil(k/3); col = mod(k-1, 3) + 1;
%         ax_bogie = axes('Parent', pnl_gallery, 'Units', 'normalized', ...
%                         'Position', [(col-1)*0.33 + 0.02, (2-row)*0.45 + 0.05, 0.30, 0.38]);
% 
%         draw_bogie_legend(ax_bogie, movements_to_draw{k});
%     end
% 
% end

% classificazione in base ai rapporti e alla FFT
% function generate_defect_classification_report(DB, CFG)
%     if isempty(DB), msgbox('Database vuoto.'); return; end
% 
%     wb = waitbar(0, 'Classificazione difetti in corso...');
%     n_db = length(DB);
% 
%     % Soglie classificazione
%     THR_LAT_VERT  = 0.6;   % ratio lat/vert sopra cui è laterale
%     THR_ASYM_HIGH = 2.0;   % ratio SX/DX sopra cui è "Rotaia SX"
%     THR_ASYM_LOW  = 0.5;   % ratio SX/DX sotto cui è "Rotaia DX"
%     THR_PITCH     = 2.0;   % ratio Front/Rear sopra cui è beccheggio
% 
%     % Soglie lambda (metri)
%     L_GIUNTO      = 0.5;   % λ < 0.5m
%     L_IRREG       = 1;   %  λ < 1m
%     L_DEFORM      = 2.0;   % 1.5 <= λ < 2m
%                            % λ >= 4.0m → Cedimento
% 
%     fs_space = 1 / CFG.SPATIAL_RES;
% 
%     SummaryData = struct('ID', {}, 'Pos', {}, 'Amp', {}, ...
%         'TipoStrutturale', {}, 'Lambda_SX', {}, 'Lambda_DX', {}, ...
%         'Lambda_LAT', {}, 'NaturaSpettrale_SX', {}, ...
%         'NaturaSpettrale_DX', {}, 'Ratio_SX_DX', {}, ...
%         'Ratio_FR_SX', {}, 'Ratio_FR_DX', {}, 'Ratio_Lat_Vert', {});
% 
%     for i = 1:n_db
%         waitbar(i/n_db, wb);
%         Defect = DB(i);
% 
% 
%         % Salta difetti con troppo pochi passaggi per un'analisi affidabile
%         if length(Defect.History) < 50
%             SummaryData(i).ID               = Defect.ID_PK;
%             SummaryData(i).Pos              = Defect.Avg_Pos;
%             SummaryData(i).Amp              = Defect.Max_Severity;
%             SummaryData(i).TipoStrutturale  = 'N/D (run insufficienti)';
%             SummaryData(i).Lambda_SX        = 0;
%             SummaryData(i).Lambda_DX        = 0;
%             SummaryData(i).Lambda_LAT       = 0;
%             SummaryData(i).NaturaSpettrale_SX = 'N/D';
%             SummaryData(i).NaturaSpettrale_DX = 'N/D';
%             SummaryData(i).Ratio_SX_DX     = 1;
%             SummaryData(i).Ratio_FR_SX     = 1;
%             SummaryData(i).Ratio_FR_DX     = 1;
%             SummaryData(i).Ratio_Lat_Vert  = 0;
%             continue;
%         end
% 
% 
%         % Accumulo features su tutti i passaggi
%         A_SX_F_all = []; A_SX_R_all = [];
%         A_DX_F_all = []; A_DX_R_all = [];
%         A_LAT_DXF_all = []; A_LAT_DXR_all = [];
%         A_LAT_SXF_all = []; A_LAT_SXR_all = [];
%         % Spettri accumulati (somma pesata su tutti i passaggi)
%         Spec_SX  = []; Spec_DX  = []; Spec_LAT = [];
%         freq_vec_SX = []; freq_vec_DX = []; freq_vec_LAT = [];
%         W_SX = 0; W_DX = 0; W_LAT = 0;
% 
%         for k = 1:length(Defect.History)
%             run = Defect.History(k);
%             if ~isfield(run.Data, 'Filt'), continue; end
%             F = run.Data.Filt;
% 
% 
%             % --- CONTROLLO LUNGHEZZA SEGNALE ---
%             % Lunghezza attesa: 2 * WINDOW_SIZE / SPATIAL_RES
%             N_expected = round(2 * CFG.WINDOW_SIZE / CFG.SPATIAL_RES);
%             % Controlla sul primo sensore disponibile
%             check_sensors = {'left_sensor_front', 'right_sensor_front'};
%             sig_len = 0;
%             for cs = 1:length(check_sensors)
%                 if isfield(F, check_sensors{cs})
%                     sig_len = length(double(F.(check_sensors{cs})));
%                     break;
%                 end
%             end
%             % Salta il passaggio se il segnale è troppo corto (< 80% dell'atteso)
%             if sig_len < N_expected * 0.99
%                 continue;
%             end
% 
%             % --- AMPIEZZE ---
%             A_SX_F = get_amp(F, 'left_sensor_front');
%             A_SX_R = get_amp(F, 'left_sensor_rear');
%             A_DX_F = get_amp(F, 'right_sensor_front');
%             A_DX_R = get_amp(F, 'right_sensor_rear');
%             A_LAT_DXF = get_amp(F, 'right_sensor_front_lat');
%             A_LAT_DXR = get_amp(F, 'right_sensor_rear_lat');
%             A_LAT_SXF = get_amp(F, 'left_sensor_front_lat');
%             A_LAT_SXR = get_amp(F, 'left_sensor_rear_lat');
% 
%             A_SX_F_all(end+1) = A_SX_F;
%             A_SX_R_all(end+1) = A_SX_R;
%             A_DX_F_all(end+1) = A_DX_F;
%             A_DX_R_all(end+1) = A_DX_R;
%             A_LAT_DXF_all(end+1) = A_LAT_DXF;
%             A_LAT_DXR_all(end+1) = A_LAT_DXR;
%             A_LAT_SXF_all(end+1) = A_LAT_SXF;
%             A_LAT_SXR_all(end+1) = A_LAT_SXR;
% 
%             % Peso del passaggio = ampiezza media verticale
%             w_pass_SX  = A_SX_F + A_SX_R;
%             w_pass_DX  = A_DX_F + A_DX_R;
%             w_pass_LAT = A_LAT_DXF + A_LAT_DXR + A_LAT_SXF + A_LAT_SXR;
% 
% [s_sx, f_sx] = get_spectrum(F, ...
%                 {'left_sensor_front','left_sensor_rear'}, ...
%                 [A_SX_F, A_SX_R], fs_space);
%             if ~isempty(s_sx)
%                 if isempty(Spec_SX)
%                     Spec_SX = zeros(size(s_sx)); freq_vec_SX = f_sx;
%                 end
%                 if length(s_sx) == length(Spec_SX)
%                     Spec_SX = Spec_SX + s_sx * w_pass_SX;
%                     W_SX    = W_SX + w_pass_SX;
%                 end
%             end
% 
%             [s_dx, f_dx] = get_spectrum(F, ...
%                 {'right_sensor_front','right_sensor_rear'}, ...
%                 [A_DX_F, A_DX_R], fs_space);
%             if ~isempty(s_dx)
%                 if isempty(Spec_DX)
%                     Spec_DX = zeros(size(s_dx)); freq_vec_DX = f_dx;
%                 end
%                 if length(s_dx) == length(Spec_DX)
%                     Spec_DX = Spec_DX + s_dx * w_pass_DX;
%                     W_DX    = W_DX + w_pass_DX;
%                 end
%             end
% 
%             [s_lat, f_lat] = get_spectrum(F, ...
%                 {'right_sensor_front_lat','right_sensor_rear_lat', ...
%                  'left_sensor_front_lat','left_sensor_rear_lat'}, ...
%                 [A_LAT_DXF, A_LAT_DXR, A_LAT_SXF, A_LAT_SXR], fs_space);
%             if ~isempty(s_lat)
%                 if isempty(Spec_LAT)
%                     Spec_LAT = zeros(size(s_lat)); freq_vec_LAT = f_lat;
%                 end
%                 if length(s_lat) == length(Spec_LAT)
%                     Spec_LAT = Spec_LAT + s_lat * w_pass_LAT;
%                     W_LAT    = W_LAT + w_pass_LAT;
%                 end
%             end
%         end
% 
% 
%         % --- CONTROLLO: se nessun passaggio valido, salta il difetto ---
%         if isempty(A_SX_F_all)
%             SummaryData(i).ID               = Defect.ID_PK;
%             SummaryData(i).Pos              = Defect.Avg_Pos;
%             SummaryData(i).Amp              = Defect.Max_Severity;
%             SummaryData(i).TipoStrutturale  = 'N/D (segnale corto)';
%             SummaryData(i).Lambda_SX        = 0;
%             SummaryData(i).Lambda_DX        = 0;
%             SummaryData(i).Lambda_LAT       = 0;
%             SummaryData(i).NaturaSpettrale_SX = 'N/D';
%             SummaryData(i).NaturaSpettrale_DX = 'N/D';
%             SummaryData(i).Ratio_SX_DX     = 1;
%             SummaryData(i).Ratio_FR_SX     = 1;
%             SummaryData(i).Ratio_FR_DX     = 1;
%             SummaryData(i).Ratio_Lat_Vert  = 0;
%             continue;
%         end
% 
%         % --- MEDIA DELLE FEATURES SUI PASSAGGI ---
%         A_SX_F = mean(A_SX_F_all); A_SX_R = mean(A_SX_R_all);
%         A_DX_F = mean(A_DX_F_all); A_DX_R = mean(A_DX_R_all);
%         A_LAT  = mean([A_LAT_DXF_all, A_LAT_DXR_all, ...
%                        A_LAT_SXF_all, A_LAT_SXR_all]);
%         A_VERT = mean([A_SX_F_all, A_SX_R_all, A_DX_F_all, A_DX_R_all]);
% 
%         % Lambda dal picco dello spettro sommato
%         Lambda_SX  = peak_lambda_from_spectrum(Spec_SX,  freq_vec_SX,  W_SX,  CFG);
%         Lambda_DX  = peak_lambda_from_spectrum(Spec_DX,  freq_vec_DX,  W_DX,  CFG);
%         Lambda_LAT = peak_lambda_from_spectrum(Spec_LAT, freq_vec_LAT, W_LAT, CFG);
% 
%         % Sanity check: lambda fisicamente impossibile → azzera
%         LAMBDA_MAX_FISICO = CFG.WINDOW_SIZE * 1.5; % max ragionevole = 7.5m
%         if Lambda_SX  > LAMBDA_MAX_FISICO, Lambda_SX  = 0; end
%         if Lambda_DX  > LAMBDA_MAX_FISICO, Lambda_DX  = 0; end
%         if Lambda_LAT > LAMBDA_MAX_FISICO, Lambda_LAT = 0; end
% 
%         % --- RATIO ---
%         denom_sxdx = A_SX_F + A_SX_R + A_DX_F + A_DX_R;
%         Ratio_SX_DX   = safe_ratio(A_SX_F+A_SX_R, A_DX_F+A_DX_R);
%         Ratio_FR_SX   = safe_ratio(A_SX_F, A_SX_R);
%         Ratio_FR_DX   = safe_ratio(A_DX_F, A_DX_R);
%         Ratio_Lat_Vert = safe_ratio(A_LAT, A_VERT);
% 
%         % --- CLASSIFICAZIONE STRUTTURALE ---
%         if Ratio_Lat_Vert > THR_LAT_VERT
%             % Determina segno dai segnali laterali medi
%             sig_lat_f = get_sign_mean(Defect, 'right_sensor_front_lat', ...
%                                               'left_sensor_front_lat');
%             sig_lat_r = get_sign_mean(Defect, 'right_sensor_rear_lat', ...
%                                               'left_sensor_rear_lat');
%             if sig_lat_f * sig_lat_r > 0
%                 tipo = 'Colpo Laterale';
%             else
%                 tipo = 'Serpeggio';
%             end
%         elseif Ratio_SX_DX > THR_ASYM_HIGH
%             tipo = 'Rotaia SX';
%         elseif Ratio_SX_DX < THR_ASYM_LOW
%             tipo = 'Rotaia DX';
%         elseif Ratio_FR_SX > THR_PITCH || Ratio_FR_DX > THR_PITCH
%             tipo = 'Front>>Rear';
%         else
%             tipo = 'Front simile rear';
%         end
% 
%         % --- NATURA SPETTRALE ---
%         nat_SX  = lambda_to_label(Lambda_SX,  L_GIUNTO, L_IRREG, L_DEFORM);
%         nat_DX  = lambda_to_label(Lambda_DX,  L_GIUNTO, L_IRREG, L_DEFORM);
% 
%         % --- SALVATAGGIO ---
%         SummaryData(i).ID               = Defect.ID_PK;
%         SummaryData(i).Pos              = Defect.Avg_Pos;
%         SummaryData(i).Amp              = Defect.Max_Severity;
%         SummaryData(i).TipoStrutturale  = tipo;
%         SummaryData(i).Lambda_SX        = Lambda_SX;
%         SummaryData(i).Lambda_DX        = Lambda_DX;
%         SummaryData(i).Lambda_LAT       = Lambda_LAT;
%         SummaryData(i).NaturaSpettrale_SX = nat_SX;
%         SummaryData(i).NaturaSpettrale_DX = nat_DX;
%         SummaryData(i).Ratio_SX_DX     = Ratio_SX_DX;
%         SummaryData(i).Ratio_FR_SX     = Ratio_FR_SX;
%         SummaryData(i).Ratio_FR_DX     = Ratio_FR_DX;
%         SummaryData(i).Ratio_Lat_Vert  = Ratio_Lat_Vert;
%     end
%     close(wb);
% 
%     % =====================================================================
%     % DASHBOARD
%     % =====================================================================
%     f_rep = figure('Name', 'Classificazione Difetti', 'Color', 'w', ...
%         'WindowState', 'maximized');
%     tg = uitabgroup(f_rep);
% 
%    % ---------------------------------------------------------
%     % TAB 1: MAPPA + TORTA
%     % ---------------------------------------------------------
%     tab1 = uitab(tg, 'Title', 'Panoramica');
% 
%     % --- RIGA SUPERIORE: Torta tipo strutturale + Scatter Severità vs Lambda ---
%     tipi = string({SummaryData.TipoStrutturale});
%     nat_sx = string({SummaryData.NaturaSpettrale_SX});
%     nat_dx = string({SummaryData.NaturaSpettrale_DX});
% 
%     % Escludi N/D dalla torta
%     mask_validi = ~contains(tipi, 'N/D');
%     tipi_validi = tipi(mask_validi);
% 
%     ax_pie = axes('Parent', tab1, 'Position', [0.03 0.42 0.28 0.52]);
%     if ~isempty(tipi_validi)
%         pie(ax_pie, categorical(tipi_validi));
%         set(findobj(ax_pie, 'Type', 'text'), 'Visible', 'off');
%         legend(ax_pie, unique(tipi_validi, 'stable'), 'Location', 'southoutside', ...
%             'FontSize', 7, 'NumColumns', 2);
%     else
%         text(ax_pie, 0.5, 0.5, 'Nessun dato valido', 'HorizontalAlignment', 'center');
%     end
%     title(ax_pie, 'Tipo Strutturale', 'FontSize', 10, 'FontWeight', 'bold');
% 
%     % Scatter Severità vs Lambda (destra, occupa 2/3 della larghezza)
%     ax_sv = axes('Parent', tab1, 'Position', [0.36 0.50 0.58 0.43]);
%     hold(ax_sv, 'on'); grid(ax_sv, 'on');
%     unique_tipi = unique(tipi, 'stable');
%     colors = lines(length(unique_tipi));
%     lambdas_sx = [SummaryData.Lambda_SX];
%     lambdas_dx = [SummaryData.Lambda_DX];
%     amps       = [SummaryData.Amp];
% 
%     for t = 1:length(unique_tipi)
%         % Escludi i N/D dal grafico lambda
%         if contains(char(unique_tipi(t)), 'N/D'), continue; end
%         mask = tipi == unique_tipi(t);
%         % Escludi anche i punti con lambda=0 (N/D mascherati)
%         mask_valid = mask & (lambdas_sx > 0 | lambdas_dx > 0);
%         if ~any(mask_valid), continue; end
%         scatter(ax_sv, lambdas_sx(mask_valid), amps(mask_valid), 50, colors(t,:), ...
%             'filled', 'DisplayName', char(unique_tipi(t)), ...
%             'MarkerFaceAlpha', 0.8);
%         scatter(ax_sv, lambdas_dx(mask_valid), amps(mask_valid), 50, colors(t,:), ...
%             'o', 'LineWidth', 1.5, 'HandleVisibility', 'off', ...
%             'MarkerFaceAlpha', 0);
%     end
% 
%     % Soglie solo se nel range
%     lam_max_vis = max([lambdas_sx, lambdas_dx]) * 1.15;
%     soglie = [L_GIUNTO, L_IRREG, L_DEFORM];
%     nomi_s = {sprintf('λ=%.1fm', L_GIUNTO), ...
%               sprintf('λ=%.1fm', L_IRREG), ...
%               sprintf('λ=%.1fm', L_DEFORM)};
%     col_s  = {'b:', 'g:', 'r:'};
%     for si = 1:3
%         if soglie(si) < lam_max_vis
%             xline(ax_sv, soglie(si), col_s{si}, 'LineWidth', 1.5, ...
%                 'DisplayName', nomi_s{si});
%         end
%     end
% 
%     xlabel(ax_sv, 'λ dominante [m]');
%     ylabel(ax_sv, 'Severità Max [m/s²]');
%     title(ax_sv, 'Severità vs λ  (● pieno=SX  ○ vuoto=DX)', ...
%         'FontWeight', 'bold', 'FontSize', 9);
%     legend(ax_sv, 'Location', 'eastoutside', 'FontSize', 8);
%     xlim(ax_sv, [0, lam_max_vis]);
% 
% 
%     % --- RIGA INFERIORE: mappa ---
%     ax_map = axes('Parent', tab1, 'Position', [0.05 0.07 0.88 0.30]);
%     hold(ax_map, 'on'); grid(ax_map, 'on');
%     unique_tipi = unique(tipi, 'stable');
%     colors = lines(length(unique_tipi));
% 
% 
% 
% 
%     for t = 1:length(unique_tipi)
%         if contains(char(unique_tipi(t)), 'N/D'), continue; end
%         mask = tipi == unique_tipi(t);
%         if ~any(mask), continue; end
%         scatter(ax_map, [SummaryData(mask).Pos]/1000, ...
%             [SummaryData(mask).Amp], 40, colors(t,:), 'filled', ...
%             'DisplayName', char(unique_tipi(t)));
%     end
% 
%     legend(ax_map, 'Location', 'bestoutside');
%     xlabel(ax_map, 'PK [km]'); ylabel(ax_map, 'Severità [m/s^2]');
%     title(ax_map, 'Mappa Difetti per Tipo', 'FontWeight', 'bold');
%     ax_map.XAxis.Exponent = 0;
%     % ---------------------------------------------------------
%     % TAB 2: SCATTER RATIO
%     % ---------------------------------------------------------
%     tab2 = uitab(tg, 'Title', 'Analisi Ratio');
% 
%     ratios_sxdx = [SummaryData.Ratio_SX_DX];
%     ratios_fr   = max([[SummaryData.Ratio_FR_SX]; [SummaryData.Ratio_FR_DX]]);
%     ratios_lv   = [SummaryData.Ratio_Lat_Vert];
%     amps        = [SummaryData.Amp];
% 
%     % Scatter SX/DX vs FR
% 
% 
%     ax_r1 = subplot(1, 2, 1, 'Parent', tab2);
%     hold(ax_r1, 'on'); grid(ax_r1, 'on');
%     for t = 1:length(unique_tipi)
%         if contains(char(unique_tipi(t)), 'N/D'), continue; end
%         mask = tipi == unique_tipi(t);
%         if ~any(mask), continue; end
%         scatter(ax_r1, ratios_sxdx(mask), ratios_fr(mask), ...
%             40, colors(t,:), 'filled', 'DisplayName', char(unique_tipi(t)));
%     end
% 
% 
%     xline(ax_r1, THR_ASYM_HIGH, 'k--', 'LineWidth', 1, 'DisplayName', sprintf('SX/DX=%.1f', THR_ASYM_HIGH));
%     xline(ax_r1, THR_ASYM_LOW,  'k--', 'LineWidth', 1, 'DisplayName', sprintf('SX/DX=%.1f', THR_ASYM_LOW));
%     yline(ax_r1, THR_PITCH, 'r--', 'LineWidth', 1, 'DisplayName', sprintf('FR=%.1f (Becch.)', THR_PITCH));
%     xlabel(ax_r1, 'Ratio SX/DX'); ylabel(ax_r1, 'Ratio Front/Rear (max)');
%     title(ax_r1, 'Simmetria Trasversale vs Longitudinale');
%     legend(ax_r1, 'Location', 'bestoutside'); 
%     set(ax_r1, 'XScale', 'log'); set(ax_r1, 'YScale', 'log');
% 
%     % Scatter Lat/Vert vs Severità
% 
% 
%     ax_r2 = subplot(1, 2, 2, 'Parent', tab2);
%     hold(ax_r2, 'on'); grid(ax_r2, 'on');
%     for t = 1:length(unique_tipi)
%         if contains(char(unique_tipi(t)), 'N/D'), continue; end
%         mask = tipi == unique_tipi(t);
%         if ~any(mask), continue; end
%         scatter(ax_r2, ratios_lv(mask), amps(mask), ...
%             40, colors(t,:), 'filled', 'DisplayName', char(unique_tipi(t)));
%     end
% 
% 
%     xline(ax_r2, THR_LAT_VERT, 'k--', 'LineWidth', 1);
%     xlabel(ax_r2, 'Ratio Laterale/Verticale');
%     ylabel(ax_r2, 'Severità Max [m/s^2]');
%     title(ax_r2, 'Componente Laterale vs Severità');
%     legend(ax_r2, 'Location', 'bestoutside');
%     % --- DATATIP TAB 2 ---
%     dcm2 = datacursormode(f_rep);
%     set(dcm2, 'Enable', 'on', 'UpdateFcn', ...
%         @(~, evt) classification_datatip(evt, SummaryData, tipi));
%     % ---------------------------------------------------------
%     % TAB 3: LAMBDA SCATTER
%     % ---------------------------------------------------------
%     tab3 = uitab(tg, 'Title', 'Analisi Spettrale');
% 
%     lambdas_sx  = [SummaryData.Lambda_SX];
%     lambdas_dx  = [SummaryData.Lambda_DX];
% 
%     ax_l = axes('Parent', tab3, 'Position', [0.08 0.12 0.55 0.80]);
%     hold(ax_l, 'on'); grid(ax_l, 'on');
%     for t = 1:length(unique_tipi)
%         if contains(char(unique_tipi(t)), 'N/D'), continue; end
%         mask = tipi == unique_tipi(t);
%         mask_valid = mask & (lambdas_sx > 0) & (lambdas_dx > 0);
%         if ~any(mask_valid), continue; end
%         scatter(ax_l, lambdas_sx(mask_valid), lambdas_dx(mask_valid), ...
%             max(amps(mask_valid)*3, 20), colors(t,:), 'filled', ...
%             'DisplayName', char(unique_tipi(t)), 'MarkerFaceAlpha', 0.7);
%     end
% 
%     % Linee soglia lambda
%     xline(ax_l, L_GIUNTO, 'b:', 'LineWidth', 1.5, 'DisplayName', ...
%         sprintf('λ=%.1fm', L_GIUNTO));
%     xline(ax_l, L_IRREG,  'g:', 'LineWidth', 1.5, 'DisplayName', ...
%         sprintf('λ=%.1fm', L_IRREG));
%     xline(ax_l, L_DEFORM, 'r:', 'LineWidth', 1.5, 'DisplayName', ...
%         sprintf('λ=%.1fm', L_DEFORM));
%     yline(ax_l, L_GIUNTO, 'b:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
%     yline(ax_l, L_IRREG,  'g:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
%     yline(ax_l, L_DEFORM, 'r:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
% 
%     % Limiti adattivi escludendo lambda=0
%     valid_lam_l = [lambdas_sx(lambdas_sx > 0), lambdas_dx(lambdas_dx > 0)];
%     if isempty(valid_lam_l), valid_lam_l = [0.1]; end
%     lam_max_l = max(valid_lam_l) * 1.15;
%     plot(ax_l, [0 lam_max_l], [0 lam_max_l], 'k--', 'HandleVisibility', 'off');
%     xlim(ax_l, [0, lam_max_l]);
%     ylim(ax_l, [0, lam_max_l]);
%     axis(ax_l, 'square');
% 
%     xlabel(ax_l, 'λ dominante SX [m]');
%     ylabel(ax_l, 'λ dominante DX [m]');
%     title(ax_l, 'Firma Spettrale SX vs DX (dim. = severità)', ...
%         'FontWeight', 'bold');
%     legend(ax_l, 'Location', 'bestoutside');
% 
%     ax_lh = axes('Parent', tab3, 'Position', [0.70 0.12 0.27 0.80]);
%     hold(ax_lh, 'on'); grid(ax_lh, 'on');
% 
% 
%     % Escludi lambda=0 dall'istogramma
%     all_lam = [lambdas_sx(lambdas_sx > 0), lambdas_dx(lambdas_dx > 0)];
%     if isempty(all_lam), all_lam = [0.1]; end
%     if max(all_lam) < 1.0
%         bin_edges = 0 : 0.05 : (max(all_lam) * 1.2);
%     elseif max(all_lam) < 3.0
%         bin_edges = 0 : 0.10 : (max(all_lam) * 1.2);
%     else
%         bin_edges = 0 : 0.20 : (max(all_lam) * 1.2);
%     end
% 
%     histogram(ax_lh, lambdas_sx, bin_edges, 'Normalization', 'count', ...
%         'EdgeColor', 'b', 'FaceColor', [0.6 0.8 1], 'DisplayName', 'SX');
%     histogram(ax_lh, lambdas_dx, bin_edges, 'Normalization', 'count', ...
%         'EdgeColor', 'r', 'FaceColor', [1 0.7 0.7], 'DisplayName', 'DX');
% 
%     soglie_lab = {sprintf('λ=%.1fm (Corto)',  L_GIUNTO), ...
%                   sprintf('λ=%.1fm (Medio)',  L_IRREG), ...
%                   sprintf('λ=%.1fm (Lungo)',  L_DEFORM)};
%     for si = 1:3
%         if soglie(si) < max(bin_edges)
%             xline(ax_lh, soglie(si), col_s{si}, 'LineWidth', 1.5, ...
%                 'DisplayName', soglie_lab{si});
%         end
%     end
% 
%     % Tick ogni bin_step sull'asse X
%     set(ax_lh, 'XTick', bin_edges(1:2:end));
%     xtickformat(ax_lh, '%.2f');
%     xtickangle(ax_lh, 45);
% 
%     xlabel(ax_lh, 'λ [m]'); ylabel(ax_lh, 'Conteggio');
%     title(ax_lh, 'Distribuzione λ');
%     legend(ax_lh, 'Location', 'best', 'FontSize', 7);
% 
%     % ---------------------------------------------------------
%     % TAB 4: TABELLA DETTAGLIO
%     % ---------------------------------------------------------
%     tab4 = uitab(tg, 'Title', 'Tabella Dettaglio');
%     col_names = {'ID', 'PK [m]', 'Amp [m/s²]', 'Tipo', ...
%         'λ SX [m]', 'λ DX [m]', 'Nat. SX', 'Nat. DX', ...
%         'R SX/DX', 'R FR_SX', 'R FR_DX', 'R Lat/Vert'};
%     tab_data = cell(n_db, 12);
%     for i = 1:n_db
%         s = SummaryData(i);
%         tab_data(i,:) = {s.ID, round(s.Pos), round(s.Amp,1), ...
%             s.TipoStrutturale, round(s.Lambda_SX,2), round(s.Lambda_DX,2), ...
%             s.NaturaSpettrale_SX, s.NaturaSpettrale_DX, ...
%             round(s.Ratio_SX_DX,2), round(s.Ratio_FR_SX,2), ...
%             round(s.Ratio_FR_DX,2), round(s.Ratio_Lat_Vert,2)};
%     end
%     uitable('Parent', tab4, 'Data', tab_data, 'ColumnName', col_names, ...
%         'Units', 'normalized', 'Position', [0.01 0.01 0.98 0.98], ...
%         'RowName', [], 'FontSize', 9);
% end
function generate_defect_classification_report(DB, CFG)
    if isempty(DB), msgbox('Database vuoto.'); return; end
    wb = waitbar(0, 'Classificazione difetti in corso (Analisi Mensile)...');
    n_db = length(DB);
    
    % --- Soglie classificazione 3x3 e Ratio ---
    THR_LAT_VERT  = 0.6;   % Ratio lat/vert sopra cui è forte componente laterale
    THR_ASYM_HIGH = 2.0;   % Ratio SX/DX sopra cui è "Left"
    THR_ASYM_LOW  = 0.5;   % Ratio SX/DX sotto cui è "Right"
    THR_PITCH     = 2.0;   % Ratio Front/Rear sopra cui è "Front"
    THR_PITCH_LOW = 0.5;   % Ratio Front/Rear sotto cui è "Rear"
    
    % --- Soglie lambda (metri) ---
    L_GIUNTO      = 0.5;   % λ < 0.5m
    L_IRREG       = 1.0;   % λ < 1m
    L_DEFORM      = 2.0;   % 1.0 <= λ < 2m
    
    fs_space = 1 / CFG.SPATIAL_RES;
    
    % Inizializzazione struttura risultati completa
    SummaryData = struct('ID', {}, 'Pos', {}, 'Amp', {}, ...
        'Cella_Dominante', {}, 'Lambda_SX', {}, 'Lambda_DX', {}, ...
        'NaturaSpettrale_SX', {}, 'NaturaSpettrale_DX', {}, ...
        'Ratio_SX_DX_Avg', {}, 'Ratio_FR_Avg', {}, 'Ratio_Lat_Vert_Avg', {}, ...
        'Mese_Ultimo', {});
        
    for i = 1:n_db
        waitbar(i/n_db, wb);
        Defect = DB(i);
        
        MonthlyTracker = struct();
        
        % Spettri PSD accumulati (su tutta la vita del difetto)
        Spec_SX = []; Spec_DX = [];
        freq_vec_SX = []; freq_vec_DX = [];
        W_SX = 0; W_DX = 0;
        
        for k = 1:length(Defect.History)
            run = Defect.History(k);
            if ~isfield(run.Data, 'Filt'), continue; end
            F = run.Data.Filt;
            
            % 1. Estrazione Data
            try
                if ischar(run.Date) || isstring(run.Date)
                    dt = datetime(run.Date);
                else
                    dt = run.Date;
                end
            catch
                dt = datetime('today'); 
            end
            mese_str = char(datetime(dt, 'Format', 'yyyy_MM'));
            mese_field = ['m_', mese_str];
            
            % 2. Ampiezze Run
            A_SX_F = get_amp(F, 'left_sensor_front');
            A_SX_R = get_amp(F, 'left_sensor_rear');
            A_DX_F = get_amp(F, 'right_sensor_front');
            A_DX_R = get_amp(F, 'right_sensor_rear');
            A_LAT_DXF = get_amp(F, 'right_sensor_front_lat');
            A_LAT_DXR = get_amp(F, 'right_sensor_rear_lat');
            A_LAT_SXF = get_amp(F, 'left_sensor_front_lat');
            A_LAT_SXR = get_amp(F, 'left_sensor_rear_lat');
            
            A_VERT_MAX = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
            A_LAT_MAX  = max([A_LAT_DXF , A_LAT_DXR ,A_LAT_SXF, A_LAT_SXR]);
            
            if A_VERT_MAX < 1e-6, continue; end
            
            % 3. Ratios della singola Run
            % denom_dx   = max(A_DX_F + A_DX_R, 1e-6);
            % denom_rear = max(A_SX_R + A_DX_R, 1e-6);
            Ratio_SX_DX = (A_SX_F + A_SX_R) / max(A_DX_F + A_DX_R, 1e-6);
            Ratio_Front_Rear = (A_SX_F + A_DX_F) / max(A_SX_R+A_DX_R, 1e-6);
            Ratio_Lat_Vert = A_LAT_MAX / max(A_VERT_MAX, 1e-6);
            
            % 4. Classificazione nella Griglia 3x3
            if Ratio_SX_DX > THR_ASYM_HIGH,       pos_x = 'Left';
            elseif Ratio_SX_DX < THR_ASYM_LOW,    pos_x = 'Right';
            else,                                 pos_x = 'Center'; end
            
            if Ratio_Front_Rear > THR_PITCH,      pos_y = 'Front';
            elseif Ratio_Front_Rear < THR_PITCH_LOW, pos_y = 'Rear';
            else,                                 pos_y = 'Center'; end
            
            cella_3x3 = sprintf('%s-%s', pos_y, pos_x);
            
            % 5. Salvataggio Mensile
            if ~isfield(MonthlyTracker, mese_field)
                MonthlyTracker.(mese_field) = struct('mese_label', mese_str, ...
                    'celle_3x3', {{}}, 'ratios_x', [], 'ratios_y', [], ...
                    'ratios_lv', [], 'amp_max', 0);
            end
            MonthlyTracker.(mese_field).celle_3x3{end+1} = cella_3x3;
            MonthlyTracker.(mese_field).ratios_x(end+1)  = Ratio_SX_DX;
            MonthlyTracker.(mese_field).ratios_y(end+1)  = Ratio_Front_Rear;
            MonthlyTracker.(mese_field).ratios_lv(end+1) = Ratio_Lat_Vert;
            max_amp_run = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
            MonthlyTracker.(mese_field).amp_max = max(MonthlyTracker.(mese_field).amp_max, max_amp_run);
            
            % 6. Accumulo PSD (Periodogramma 10m) per analisi Lambda Globale
            w_pass_SX = A_SX_F + A_SX_R;
            w_pass_DX = A_DX_F + A_DX_R;
            
            [s_sx, f_sx] = get_spectrum_psd(F, {'left_sensor_front','left_sensor_rear'}, [A_SX_F, A_SX_R], CFG);
            if ~isempty(s_sx)
                if isempty(Spec_SX), Spec_SX = zeros(size(s_sx)); freq_vec_SX = f_sx; end
                if length(s_sx) == length(Spec_SX), Spec_SX = Spec_SX + s_sx * w_pass_SX; W_SX = W_SX + w_pass_SX; end
            end
            
            [s_dx, f_dx] = get_spectrum_psd(F, {'right_sensor_front','right_sensor_rear'}, [A_DX_F, A_DX_R], CFG);
            if ~isempty(s_dx)
                if isempty(Spec_DX), Spec_DX = zeros(size(s_dx)); freq_vec_DX = f_dx; end
                if length(s_dx) == length(Spec_DX), Spec_DX = Spec_DX + s_dx * w_pass_DX; W_DX = W_DX + w_pass_DX; end
            end
        end
        
        % --- RISOLUZIONE DEL DIFETTO SULL'ULTIMO MESE ---
        campi_mesi = sort(fieldnames(MonthlyTracker));
        
        if isempty(campi_mesi)
            SummaryData(i).ID = Defect.ID_PK; SummaryData(i).Pos = Defect.Avg_Pos;
            SummaryData(i).Cella_Dominante = 'N/D'; SummaryData(i).Lambda_SX = 0; SummaryData(i).Lambda_DX = 0;
            continue;
        end
        
        ultimo_mese = MonthlyTracker.(campi_mesi{end});
        cella_dominante_mese = char(mode(categorical(ultimo_mese.celle_3x3)));
        
        Lambda_SX = peak_lambda_from_spectrum(Spec_SX, freq_vec_SX, W_SX, CFG);
        Lambda_DX = peak_lambda_from_spectrum(Spec_DX, freq_vec_DX, W_DX, CFG);
        
        LAMBDA_MAX_FISICO = CFG.WINDOW_SIZE * 1.5; 
        if Lambda_SX > LAMBDA_MAX_FISICO, Lambda_SX = 0; end
        if Lambda_DX > LAMBDA_MAX_FISICO, Lambda_DX = 0; end
        
        nat_SX = lambda_to_label(Lambda_SX, L_GIUNTO, L_IRREG, L_DEFORM);
        nat_DX = lambda_to_label(Lambda_DX, L_GIUNTO, L_IRREG, L_DEFORM);
        
        SummaryData(i).ID               = Defect.ID_PK;
        SummaryData(i).Pos              = Defect.Avg_Pos;
        SummaryData(i).Amp              = ultimo_mese.amp_max;
        SummaryData(i).Cella_Dominante  = cella_dominante_mese;
        SummaryData(i).Lambda_SX        = Lambda_SX;
        SummaryData(i).Lambda_DX        = Lambda_DX;
        SummaryData(i).NaturaSpettrale_SX = nat_SX;
        SummaryData(i).NaturaSpettrale_DX = nat_DX;
        SummaryData(i).Ratio_SX_DX_Avg  = mean(ultimo_mese.ratios_x);
        SummaryData(i).Ratio_FR_Avg     = mean(ultimo_mese.ratios_y);
        SummaryData(i).Ratio_Lat_Vert_Avg = mean(ultimo_mese.ratios_lv);
        SummaryData(i).Mese_Ultimo      = ultimo_mese.mese_label;
    end
    close(wb);
    
    % =====================================================================
    % DASHBOARD
    % =====================================================================
    f_rep = figure('Name', 'Classificazione Difetti (Evoluzione 3x3)', 'Color', 'w', 'WindowState', 'maximized');
    tg = uitabgroup(f_rep);
    
    % --- Filtro Dati Validi ---
    celle = string({SummaryData.Cella_Dominante});
    mask_validi = ~contains(celle, 'N/D') & strlength(celle) > 1;
    celle_valide = celle(mask_validi);
    cat_uniche = unique(celle_valide, 'stable');
    colors = lines(max(1, length(cat_uniche)));
    
    % ---------------------------------------------------------
    % TAB 1: PANORAMICA (Torta + Mappa PK vs Lambda)
    % ---------------------------------------------------------
    tab1 = uitab(tg, 'Title', 'Panoramica & Mappa');
    
    % Torta
    ax_pie = axes('Parent', tab1, 'Position', [0.03 0.45 0.28 0.48]);
    if ~isempty(celle_valide)
        pie(ax_pie, categorical(celle_valide));
        set(findobj(ax_pie, 'Type', 'text'), 'Visible', 'off');
        legend(ax_pie, unique(celle_valide, 'stable'), 'Location', 'southoutside', 'FontSize', 8, 'NumColumns', 2);
    else
        text(ax_pie, 0.5, 0.5, 'Nessun dato valido', 'HorizontalAlignment', 'center');
    end
    title(ax_pie, 'Matrice 3x3 (Ultimo Mese)', 'FontSize', 11, 'FontWeight', 'bold');
    
    % Mappa
    ax_map = axes('Parent', tab1, 'Position', [0.38 0.15 0.58 0.75]);
    hold(ax_map, 'on'); grid(ax_map, 'on');
    posizioni = [SummaryData.Pos] / 1000;
    lambdas_max = max([SummaryData.Lambda_SX; SummaryData.Lambda_DX]); 
    
    for t = 1:length(cat_uniche)
        mask = (celle == cat_uniche(t)) & (lambdas_max > 0);
        if ~any(mask), continue; end
        scatter(ax_map, posizioni(mask), lambdas_max(mask), 60, colors(t,:), 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 0.5, 'DisplayName', char(cat_uniche(t)));
    end
    
    lam_max_vis = max([0.1, max(lambdas_max) * 1.15]);
    yline(ax_map, L_GIUNTO, 'b:', 'LineWidth', 1.5, 'DisplayName', sprintf('Giunto (λ=%.1f)', L_GIUNTO));
    yline(ax_map, L_IRREG,  'g:', 'LineWidth', 1.5, 'DisplayName', sprintf('Irreg (λ=%.1f)', L_IRREG));
    yline(ax_map, L_DEFORM, 'r:', 'LineWidth', 1.5, 'DisplayName', sprintf('Deform (λ=%.1f)', L_DEFORM));
    
    legend(ax_map, 'Location', 'eastoutside', 'FontSize', 9);
    xlabel(ax_map, 'PK [km]', 'FontWeight', 'bold'); ylabel(ax_map, '\lambda Dominante [m]', 'FontWeight', 'bold');
    title(ax_map, 'Mappa Difetti: PK vs Lunghezza d''Onda (Colore = Area 3x3)', 'FontWeight', 'bold');
    ax_map.XAxis.Exponent = 0; ylim(ax_map, [0, lam_max_vis]);

    % ---------------------------------------------------------
    % TAB 2: ANALISI RATIO (Griglia 3x3 Visiva)
    % ---------------------------------------------------------
    tab2 = uitab(tg, 'Title', 'Analisi Ratio & Matrice');
    
    ratios_x  = [SummaryData.Ratio_SX_DX_Avg];
    ratios_y  = [SummaryData.Ratio_FR_Avg];
    ratios_lv = [SummaryData.Ratio_Lat_Vert_Avg];
    amps      = [SummaryData.Amp];
    
    % Scatter 1: La vera e propria griglia 3x3!
    ax_r1 = subplot(1, 2, 1, 'Parent', tab2);
    hold(ax_r1, 'on'); grid(ax_r1, 'on');
    for t = 1:length(cat_uniche)
        mask = (celle == cat_uniche(t));
        if ~any(mask), continue; end
        scatter(ax_r1, ratios_x(mask), ratios_y(mask), 50, colors(t,:), 'filled', ...
            'MarkerEdgeColor', 'k', 'DisplayName', char(cat_uniche(t)));
    end
    
    % Disegno della Griglia 3x3
    xline(ax_r1, THR_ASYM_HIGH, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Left');
    xline(ax_r1, THR_ASYM_LOW,  'k--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Right');
    yline(ax_r1, THR_PITCH,     'k-',  'LineWidth', 1.5, 'DisplayName', 'Soglia Front');
    yline(ax_r1, THR_PITCH_LOW, 'k-',  'LineWidth', 1.5, 'DisplayName', 'Soglia Rear');
    
    set(ax_r1, 'XScale', 'log', 'YScale', 'log');
    xlabel(ax_r1, 'Ratio SX / DX (Log)', 'FontWeight', 'bold'); 
    ylabel(ax_r1, 'Ratio Front / Rear (Log)', 'FontWeight', 'bold');
    title(ax_r1, 'Visualizzazione Matrice 3x3 (Ultimo Mese)', 'FontWeight', 'bold');
    legend(ax_r1, 'Location', 'bestoutside');
    
    % Scatter 2: Componente Laterale
    ax_r2 = subplot(1, 2, 2, 'Parent', tab2);
    hold(ax_r2, 'on'); grid(ax_r2, 'on');
    for t = 1:length(cat_uniche)
        mask = (celle == cat_uniche(t));
        if ~any(mask), continue; end
        scatter(ax_r2, ratios_lv(mask), amps(mask), 50, colors(t,:), 'filled', 'DisplayName', char(cat_uniche(t)));
    end
    xline(ax_r2, THR_LAT_VERT, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Soglia Laterale Elevata');
    xlabel(ax_r2, 'Ratio Laterale / Verticale', 'FontWeight', 'bold');
    ylabel(ax_r2, 'Severità Max [m/s^2]', 'FontWeight', 'bold');
    title(ax_r2, 'Impatto Componente Laterale', 'FontWeight', 'bold');
    legend(ax_r2, 'Location', 'bestoutside');

    % ---------------------------------------------------------
    % TAB 3: ANALISI SPETTRALE (Firme SX vs DX)
    % ---------------------------------------------------------
    tab3 = uitab(tg, 'Title', 'Analisi Spettrale');
    lambdas_sx = [SummaryData.Lambda_SX];
    lambdas_dx = [SummaryData.Lambda_DX];
    
    ax_l = axes('Parent', tab3, 'Position', [0.08 0.12 0.55 0.80]);
    hold(ax_l, 'on'); grid(ax_l, 'on');
    for t = 1:length(cat_uniche)
        mask = (celle == cat_uniche(t)) & (lambdas_sx > 0) & (lambdas_dx > 0);
        if ~any(mask), continue; end
        scatter(ax_l, lambdas_sx(mask), lambdas_dx(mask), max(amps(mask)*3, 20), colors(t,:), 'filled', ...
            'DisplayName', char(cat_uniche(t)), 'MarkerFaceAlpha', 0.8, 'MarkerEdgeColor', 'k');
    end
    
    xline(ax_l, L_GIUNTO, 'b:', 'LineWidth', 1.5, 'DisplayName', sprintf('λ=%.1fm', L_GIUNTO));
    xline(ax_l, L_IRREG,  'g:', 'LineWidth', 1.5, 'DisplayName', sprintf('λ=%.1fm', L_IRREG));
    xline(ax_l, L_DEFORM, 'r:', 'LineWidth', 1.5, 'DisplayName', sprintf('λ=%.1fm', L_DEFORM));
    yline(ax_l, L_GIUNTO, 'b:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    yline(ax_l, L_IRREG,  'g:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    yline(ax_l, L_DEFORM, 'r:', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    
    lam_max_l = max([0.1, lambdas_sx, lambdas_dx]) * 1.15;
    plot(ax_l, [0 lam_max_l], [0 lam_max_l], 'k--', 'HandleVisibility', 'off');
    xlim(ax_l, [0, lam_max_l]); ylim(ax_l, [0, lam_max_l]); axis(ax_l, 'square');
    
    xlabel(ax_l, '\lambda dominante SX [m]', 'FontWeight', 'bold');
    ylabel(ax_l, '\lambda dominante DX [m]', 'FontWeight', 'bold');
    title(ax_l, 'Firma Spettrale SX vs DX (Dimensione = Severità)', 'FontWeight', 'bold');
    legend(ax_l, 'Location', 'bestoutside');
    
    % Istogrammi Spettrali
    ax_lh = axes('Parent', tab3, 'Position', [0.70 0.12 0.27 0.80]);
    hold(ax_lh, 'on'); grid(ax_lh, 'on');
    all_lam = [lambdas_sx(lambdas_sx > 0), lambdas_dx(lambdas_dx > 0)];
    if isempty(all_lam), all_lam = [0.1]; end
    if max(all_lam) < 1.0, bin_edges = 0 : 0.05 : (max(all_lam) * 1.2);
    elseif max(all_lam) < 3.0, bin_edges = 0 : 0.10 : (max(all_lam) * 1.2);
    else, bin_edges = 0 : 0.20 : (max(all_lam) * 1.2); end
    
    histogram(ax_lh, lambdas_sx(lambdas_sx>0), bin_edges, 'Normalization', 'count', 'EdgeColor', 'b', 'FaceColor', [0.6 0.8 1], 'DisplayName', 'SX');
    histogram(ax_lh, lambdas_dx(lambdas_dx>0), bin_edges, 'Normalization', 'count', 'EdgeColor', 'r', 'FaceColor', [1 0.7 0.7], 'DisplayName', 'DX');
    
    xlabel(ax_lh, '\lambda [m]', 'FontWeight', 'bold'); ylabel(ax_lh, 'Conteggio', 'FontWeight', 'bold');
    title(ax_lh, 'Distribuzione \lambda', 'FontWeight', 'bold'); legend(ax_lh, 'Location', 'best', 'FontSize', 8);

    % ---------------------------------------------------------
    % TAB 4: TABELLA DETTAGLIO
    % ---------------------------------------------------------
    tab4 = uitab(tg, 'Title', 'Tabella Dettaglio Mensile');
    col_names = {'ID', 'PK [m]', 'Amp Max [m/s²]', 'Cella 3x3 (Ultimo Mese)', ...
        'Mese', 'λ SX [m]', 'λ DX [m]', 'Nat. SX', 'Nat. DX', ...
        'Ratio SX/DX', 'Ratio FR', 'Ratio Lat/Vert'};
    
    tab_data = cell(n_db, 12);
    for i = 1:n_db
        s = SummaryData(i);
        if isempty(s.Cella_Dominante), continue; end
        tab_data(i,:) = {s.ID, round(s.Pos), round(s.Amp,1), ...
            s.Cella_Dominante, s.Mese_Ultimo, round(s.Lambda_SX,2), round(s.Lambda_DX,2), ...
            s.NaturaSpettrale_SX, s.NaturaSpettrale_DX, ...
            round(s.Ratio_SX_DX_Avg,2), round(s.Ratio_FR_Avg,2), round(s.Ratio_Lat_Vert_Avg,2)};
    end
    uitable('Parent', tab4, 'Data', tab_data, 'ColumnName', col_names, ...
        'Units', 'normalized', 'Position', [0.01 0.01 0.98 0.98], ...
        'RowName', [], 'FontSize', 9);
end

% =========================================================================
% FUNZIONI ACCESSORIE 
% =========================================================================

% =========================================================================
% PCA HELPER STANDALONE - Smista i passaggi per direzione (forward/backward)
% =========================================================================
function [idx_fwd, idx_bwd] = sort_runs_by_direction(History)
    n_runs = length(History);
    idx_fwd = false(n_runs, 1);
    idx_bwd = false(n_runs, 1);
    
    for i = 1:n_runs
        run_i = History(i);
        d = run_i.Data;
        if ~isfield(d, 'Filt'), continue; end
        Fd = d.Filt;
        
        ori = '';
        if isfield(run_i, 'orientation') && ~isempty(run_i.orientation)
            ori = lower(strtrim(char(run_i.orientation)));
        elseif isfield(d, 'orientation') && ~isempty(d.orientation)
            ori = lower(strtrim(char(d.orientation)));
        end
        
        if contains(ori, 'forward')
            idx_fwd(i) = true;
        elseif contains(ori, 'backward')
            idx_bwd(i) = true;
        else
            % Fallback: confronto RMS laterali front
            rms_r = 0; rms_l = 0;
            if isfield(Fd, 'right_sensor_front_lat') && ~isempty(Fd.right_sensor_front_lat)
                s = double(Fd.right_sensor_front_lat); s = s(isfinite(s));
                if ~isempty(s), rms_r = sqrt(mean(s.^2)); end
            end
            if isfield(Fd, 'left_sensor_front_lat') && ~isempty(Fd.left_sensor_front_lat)
                s = double(Fd.left_sensor_front_lat); s = s(isfinite(s));
                if ~isempty(s), rms_l = sqrt(mean(s.^2)); end
            end
            if     rms_r > rms_l, idx_fwd(i) = true;
            elseif rms_l > rms_r, idx_bwd(i) = true;
            end
        end
    end
end

% =========================================================================
% PCA HELPER STANDALONE - Costruisce modello PCA per una direzione
% =========================================================================
% function M = build_pca_model_standalone(History, run_idx, direction, ...
%                                          spatial_res, window_size, win_m, MIN_RUNS)
%     M = [];
%     n_sel = numel(run_idx);
%     if n_sel < MIN_RUNS, return; end
% 
%     N_GRID = 333;
%     n_chan = 6;
%     x_grid = linspace(-window_size, window_size, N_GRID);
%     win_samples = max(3, round(win_m / spatial_res));
% 
%     switch lower(direction)
%         case 'forward'
%             lat_F_field = 'right_sensor_front_lat';
%             lat_R_field = 'right_sensor_rear_lat';
%         case 'backward'
%             lat_F_field = 'left_sensor_front_lat';
%             lat_R_field = 'left_sensor_rear_lat';
%         otherwise, return;
%     end
% 
% 
%     chan_fields = {'left_sensor_front', 'right_sensor_front', lat_F_field, ...
%                    'left_sensor_rear', 'right_sensor_rear', lat_R_field};
%     X       = nan(n_sel, n_chan * N_GRID);
%     dates_v = nan(n_sel, 1);
%     valid_v = false(n_sel, 1);
% 
%     for k = 1:n_sel
%         i = run_idx(k);
%         run_i = History(i);
%         dates_v(k) = datenum(run_i.Date);
%         d = run_i.Data;
%         if ~isfield(d, 'Filt'), continue; end
%         if ~isfield(d, 'RelativeAxis') || isempty(d.RelativeAxis), continue; end
%         ax_src = double(d.RelativeAxis(:));
%         if ~issorted(ax_src) || any(~isfinite(ax_src)), continue; end
%         Fd = d.Filt;
% 
%         row    = nan(1, n_chan * N_GRID);
%         row_ok = true;
%         for c = 1:n_chan
%             fn = chan_fields{c};
%             if ~isfield(Fd, fn) || isempty(Fd.(fn)), row_ok = false; break; end
%             sig = double(Fd.(fn)(:));
%             if length(sig) ~= length(ax_src) || numel(sig) < 10, row_ok = false; break; end
%             env   = sqrt(movmean(sig.^2, win_samples));
%             env_g = interp1(ax_src, env, x_grid, 'linear', NaN);
%             if any(~isfinite(env_g)), row_ok = false; break; end
%             row((c-1)*N_GRID + 1 : c*N_GRID) = env_g;
%         end
%         if row_ok, X(k, :) = row; valid_v(k) = true; end
%     end
% 
%     X       = X(valid_v, :);
%     dates_v = dates_v(valid_v);
%     n_valid = size(X, 1);
%     if n_valid < MIN_RUNS, return; end
% 
%     % Standardizzazione per-canale
%     for c = 1:n_chan
%         seg = X(:, (c-1)*N_GRID + 1 : c*N_GRID);
%         mu_c = mean(seg(:)); sg_c = std(seg(:));
%         if sg_c < 1e-9, sg_c = 1; end
%         X(:, (c-1)*N_GRID + 1 : c*N_GRID) = (seg - mu_c) / sg_c;
%     end
% 
%     try
%         [coeffs, scores] = pca(X, 'Economy', true);
%     catch
%         return;
%     end
% 
%     [dates_sorted, ord] = sort(dates_v);
%     M = struct();
%     M.coeffs  = coeffs;
%     M.scores  = scores(ord, :);
%     M.dates   = dates_sorted;
%     M.n_valid = n_valid;
% end



function M = build_pca_model_standalone(History, run_idx, direction, ...
                                         spatial_res, window_size, win_m, MIN_RUNS, k_pca)
    M = [];
    n_sel = numel(run_idx);
    if n_sel < MIN_RUNS, return; end
    
    N_GRID = 333;
    n_chan = 6;
    x_grid = linspace(-window_size, window_size, N_GRID);
    win_samples = max(3, round(win_m / spatial_res));
    
    switch lower(direction)
        case 'forward'
            lat_F_field = 'right_sensor_front_lat';
            lat_R_field = 'right_sensor_rear_lat';
        case 'backward'
            lat_F_field = 'left_sensor_front_lat';
            lat_R_field = 'left_sensor_rear_lat';
        otherwise, return;
    end

    chan_fields = {'left_sensor_front', 'right_sensor_front', lat_F_field, ...
                   'left_sensor_rear', 'right_sensor_rear', lat_R_field};
    Xraw    = nan(n_sel, n_chan * N_GRID);
    dates_v = nan(n_sel, 1);
    valid_v = false(n_sel, 1);
    
    for k = 1:n_sel
        i = run_idx(k);
        run_i = History(i);
        dates_v(k) = datenum(run_i.Date);
        d = run_i.Data;
        if ~isfield(d, 'Filt'), continue; end
        if ~isfield(d, 'RelativeAxis') || isempty(d.RelativeAxis), continue; end
        ax_src = double(d.RelativeAxis(:));
        if ~issorted(ax_src) || any(~isfinite(ax_src)), continue; end
        Fd = d.Filt;
        
        row    = nan(1, n_chan * N_GRID);
        row_ok = true;
        for c = 1:n_chan
            fn = chan_fields{c};
            if ~isfield(Fd, fn) || isempty(Fd.(fn)), row_ok = false; break; end
            sig = double(Fd.(fn)(:));
            if length(sig) ~= length(ax_src) || numel(sig) < 10, row_ok = false; break; end
            env   = sqrt(movmean(sig.^2, win_samples));
            env_g = interp1(ax_src, env, x_grid, 'linear', NaN);
            if any(~isfinite(env_g)), row_ok = false; break; end
            row((c-1)*N_GRID + 1 : c*N_GRID) = env_g;
        end
        if row_ok, Xraw(k, :) = row; valid_v(k) = true; end
    end
    
    Xraw    = Xraw(valid_v, :);
    dates_v = dates_v(valid_v);
    n_valid = size(Xraw, 1);
    if n_valid < MIN_RUNS, return; end
    
    % --- CORREZIONE CRUCIALE: REARRANGEMENT PARALLELO (CHANNEL-SPACE PCA) ---
    Nrows = n_valid * N_GRID;
    Xpar  = zeros(Nrows, n_chan); % Righe: (passaggio x posizione) | Colonne: Canale
    run_id = zeros(Nrows, 1);
    for r = 1:n_valid
        base = (r-1)*N_GRID;
        run_id(base+1 : base+N_GRID) = r;
        for c = 1:n_chan
            cols = (c-1)*N_GRID + 1 : c*N_GRID;
            Xpar(base+1 : base+N_GRID, c) = Xraw(r, cols).';
        end
    end

    % Standardizzazione per-canale coerente
    mu_ch = mean(Xpar, 1);
    sg_ch = std(Xpar, 0, 1);
    sg_ch(sg_ch < 1e-9) = 1;
    Xpar_z = (Xpar - mu_ch) ./ sg_ch;
    
    try
        [coeffs, scores] = pca(Xpar_z, 'Economy', true);
    catch
        return;
    end
    
    % Calcolo esatto del Residuo e dell'RMSE geometrico parallelo
    k_use = min(k_pca, size(coeffs, 2));
    resid_z  = scores(:, k_use+1:end) * coeffs(:, k_use+1:end)';
    se_row   = mean(resid_z.^2, 2);
    rmse_run = sqrt(accumarray(run_id, se_row, [n_valid 1], @mean));
    
    P = size(scores, 2);
    scores_run = zeros(n_valid, P);
    for j = 1:P
        scores_run(:, j) = accumarray(run_id, scores(:, j), [n_valid 1], @mean);
    end
    
    [dates_sorted, ord] = sort(dates_v);
    rmse_sorted = rmse_run(ord);
    scores_sorted = scores_run(ord, :);
    
    M = struct();
    M.coeffs  = coeffs;
    M.scores  = scores_sorted;
    M.dates   = dates_sorted;
    M.rmse    = rmse_sorted; % Contiene il VERO RMSE
    M.n_valid = n_valid;
end

% =========================================================================
% Calcolo Bonus PCA per IPI (Trend RMSE + Excursion μ+2σ)
% =========================================================================
function [bonus_pca, info] = compute_pca_bonus_for_defect(Defect, C)
    bonus_pca = 0;
    info = struct('direction_used','none', 'k_pca',C.IPI_PCA_K, ...
                  'rmse_base',NaN, 'rmse_recent',NaN, 'pca_inc_perc',0, ...
                  'n_excursions',0, 'bonus_trend',0, 'bonus_excursion',0);
    
    History = Defect.History;
    if length(History) < C.IPI_PCA_MIN_RUNS, return; end
    
    [idx_fwd, idx_bwd] = sort_runs_by_direction(History);
    
    M = [];
    if sum(idx_fwd) >= sum(idx_bwd) && sum(idx_fwd) >= C.IPI_PCA_MIN_RUNS
        M = build_pca_model_standalone(History, find(idx_fwd), 'forward', ...
                                        C.SPATIAL_RES, C.WINDOW_SIZE, 0.5, C.IPI_PCA_MIN_RUNS, C.IPI_PCA_K);
        info.direction_used = 'forward';
    end
    if isempty(M) && sum(idx_bwd) >= C.IPI_PCA_MIN_RUNS
        M = build_pca_model_standalone(History, find(idx_bwd), 'backward', ...
                                        C.SPATIAL_RES, C.WINDOW_SIZE, 0.5, C.IPI_PCA_MIN_RUNS, C.IPI_PCA_K);
        info.direction_used = 'backward';
    end
    if isempty(M), return; end
    
    % CONGRUENTE AL 100%: L'RMSE viene estratto pronto dal modello allineato
    rmse_k = M.rmse;
    
    % --- LOGICA FINESTRE RECENT FISSO ---
    days_v   = floor(M.dates);
    days_un  = unique(days_v);
    n_days   = length(days_un);
    history_span = days_un(end) - days_un(1);
    if history_span < C.IPI_MIN_HISTORY_DAYS, return; end
    if n_days < C.IPI_MIN_DAYS, return; end
    
    rmse_daily = zeros(n_days, 1);
    for dd = 1:n_days
        rmse_daily(dd) = mean(rmse_k(days_v == days_un(dd)), 'omitnan');
    end
    
    cutoff_day  = days_un(end) - C.IPI_RECENT_DAYS;
    mask_recent = days_un >  cutoff_day;
    mask_base   = days_un <= cutoff_day;
    if ~any(mask_recent) || ~any(mask_base), return; end
    
    rmse_base   = mean(rmse_daily(mask_base),   'omitnan');
    rmse_recent = mean(rmse_daily(mask_recent), 'omitnan');
    
    % --- Bonus trend ---
    bonus_trend = 0; pca_inc = 0;
    if rmse_base > 1e-9
        pca_inc     = ((rmse_recent - rmse_base) / rmse_base) * 100;
        bonus_trend = min(C.IPI_PCA_BONUS, max(0, pca_inc * (C.IPI_PCA_BONUS / C.IPI_PCA_SENS)));
    end
    
    % --- Bonus escursione ---
    base_runs = days_v <= cutoff_day;
    mu_b = mean(rmse_k(base_runs), 'omitnan');
    sg_b = std(rmse_k(base_runs), 'omitnan');
    thr  = mu_b + 2*sg_b;
    last_d   = max(M.dates);
    rec_mask = (M.dates >= last_d - C.IPI_PCA_EXCUR_DAYS);
    n_excur  = sum(rmse_k(rec_mask) > thr);
    
    bonus_excur = 0;
    if n_excur > 0
        bonus_excur = min(C.IPI_PCA_EXCUR_BONUS, n_excur * (C.IPI_PCA_EXCUR_BONUS / 3));
    end
    
    bonus_pca = bonus_trend + bonus_excur;
    info.rmse_base       = rmse_base;
    info.rmse_recent     = rmse_recent;
    info.pca_inc_perc    = pca_inc;
    info.n_excursions    = n_excur;
    info.bonus_trend     = bonus_trend;
    info.bonus_excursion = bonus_excur;
end

% =========================================================================
% AE HELPER STANDALONE - Carica modello autoencoder per una tratta
% =========================================================================
function AE_Model = load_ae_model_for_track(track_name)
    AE_Model = struct('net', [], 'mu', [], 'sigma', [], 'v_ref', 80, 'loaded', false);
    
    model_dir = 'C:\Users\Nicco\MATLAB Drive\TESI\Autoencoder_Models';
    if isempty(track_name), return; end
    expected_file = fullfile(model_dir, sprintf('modello_%s.mat', track_name));
    if ~exist(expected_file, 'file')
        fprintf('[AE] Modello non trovato: %s\n', expected_file);
        return;
    end
    
    try
        d = load(expected_file);
        if isfield(d, 'net') && isfield(d, 'mu_global') && isfield(d, 'sigma_global')
            AE_Model.net    = d.net;
            AE_Model.mu     = d.mu_global;
            AE_Model.sigma  = d.sigma_global;
            if isfield(d, 'v_ref_model'), AE_Model.v_ref = d.v_ref_model; end
            AE_Model.loaded = true;
            fprintf('[AE] Modello caricato per tratta %s\n', track_name);
        end
    catch ME
        fprintf('[AE] Errore caricamento modello: %s\n', ME.message);
    end
end


% =========================================================================
% AE HELPER STANDALONE - Calcola Bonus IA per un singolo difetto
% =========================================================================
% function [bonus_ia, info] = compute_ae_bonus_for_defect(Defect, AE_Model, C)
% bonus_ia = 0;
% info = struct('valid_runs', 0, 'acc_recent', NaN, 'acc_base', NaN, 'n_days_ae', 0);
% 
% if ~isstruct(AE_Model) || ~AE_Model.loaded || isempty(AE_Model.net), return; end
% 
% History = Defect.History;
% n_history = length(History);
% if n_history < 2, return; end
% 
% ae_sensors      = {'left_sensor_front', 'left_sensor_rear', ...
%     'right_sensor_front', 'right_sensor_rear'};
% N_SAMPLES_AE    = 334;
% input_dim_model = length(AE_Model.mu);
% 
% AE_acc   = nan(n_history, 1);
% AE_dates = nan(n_history, 1);
% 
% for k = 1:n_history
%     run = History(k);
%     if ~isfield(run.Data, 'Filt'), continue; end
%     Fd = run.Data.Filt;
% 
%     % --- FILTRO FORWARD ---
%     rms_dx = 0; rms_sx = 0;
%     if isfield(Fd,'right_sensor_front_lat') && ~isempty(Fd.right_sensor_front_lat)
%         rms_dx = rms(double(Fd.right_sensor_front_lat));
%     end
%     if isfield(Fd,'left_sensor_front_lat') && ~isempty(Fd.left_sensor_front_lat)
%         rms_sx = rms(double(Fd.left_sensor_front_lat));
%     end
%     if ~(rms_dx > rms_sx && rms_dx > 0)
%         continue;   % salta back: AE non li ha mai visti
%     end
% 
%     % Velocità + fattore K
%     if isfield(run.Data, 'Speed') && ~isempty(run.Data.Speed) && ...
%             ~isnan(run.Data.Speed) && run.Data.Speed >= 10
%         v_treno = run.Data.Speed;
%     else
%         v_treno = AE_Model.v_ref;
%     end
%     K_vel = (v_treno / AE_Model.v_ref)^2;
% 
%     % Costruzione vettore concatenato (4 sensori × 334 campioni)
%     concat_sig = zeros(1, input_dim_model);
%     valid_run  = true;
%     for s = 1:4
%         sn = ae_sensors{s};
%         if isfield(Fd, sn) && ~isempty(Fd.(sn))
%                 sig = double(Fd.(sn));
%                 sig = sig(:)';
%                 sig = sig ./ K_vel;
%                 if length(sig) ~= N_SAMPLES_AE && length(sig) > 1
%                     x_old = linspace(0, 1, length(sig));
%                     x_new = linspace(0, 1, N_SAMPLES_AE);
%                     sig = interp1(x_old, sig, x_new, 'linear', 'extrap');
%                 elseif length(sig) <= 1
%                     sig = zeros(1, N_SAMPLES_AE);
%                 end
%                 sig = sig - mean(sig);
%             else
%                 sig = zeros(1, N_SAMPLES_AE);
%                 valid_run = false;
%             end
%             si = (s-1)*N_SAMPLES_AE + 1;
%             ei = s*N_SAMPLES_AE;
%             concat_sig(si:ei) = sig;
%         end
%         if ~valid_run, continue; end
% 
%         % Speed e Curve in coda (se modello da 1338)
%         if input_dim_model > 1336
%             if isfield(run.Data, 'Speed') && ~isempty(run.Data.Speed) && ~isnan(run.Data.Speed)
%                 concat_sig(end-1) = double(run.Data.Speed);
%             end
%             if isfield(Defect, 'Curve') && ~isempty(Defect.Curve) && ...
%                isnumeric(Defect.Curve) && ~isnan(Defect.Curve)
%                 concat_sig(end) = double(Defect.Curve);
%             end
%         end
% 
%         input_norm = (concat_sig - AE_Model.mu) ./ AE_Model.sigma;
%         try
%             reconstructed = predict(AE_Model.net, input_norm);
%         catch
%             continue;
%         end
% 
%         mse_val  = mean((input_norm - reconstructed).^2);
%         var_orig = var(input_norm);
%         if var_orig > 0
%             r2 = 1 - (mse_val / var_orig);
%             accuracy_perc = max(0, r2) * 100;
%         else
%             accuracy_perc = 0;
%         end
% 
%         AE_acc(k)   = accuracy_perc;
%         AE_dates(k) = datenum(run.Date);
%     end
% 
%     % --- NUOVA LOGICA FINESTRE: recent fisso ---
%     valid_mask = ~isnan(AE_acc);
%     if sum(valid_mask) < 2, return; end
% 
%     valid_acc_v   = AE_acc(valid_mask);
%     valid_dates_v = AE_dates(valid_mask);
%     days_v   = floor(valid_dates_v);
%     days_un  = unique(days_v);
%     n_days   = length(days_un);
%     history_span = days_un(end) - days_un(1);
%     if history_span < C.IPI_MIN_HISTORY_DAYS, return; end
%     if n_days < C.IPI_MIN_DAYS, return; end
% 
%     acc_daily = zeros(n_days, 1);
%     for d = 1:n_days
%         acc_daily(d) = mean(valid_acc_v(days_v == days_un(d)), 'omitnan');
%     end
% 
%     cutoff_day  = days_un(end) - C.IPI_RECENT_DAYS;
%     mask_recent = days_un >  cutoff_day;
%     mask_base   = days_un <= cutoff_day;
%     if ~any(mask_recent) || ~any(mask_base), return; end
% 
%     acc_recent = mean(acc_daily(mask_recent), 'omitnan');
%     acc_base   = mean(acc_daily(mask_base),   'omitnan');
% 
%     % Gate di affidabilità: se la baseline è già bassa, l'AE non ha un buon punto zero
%     %  -> bonus = 0 (modello inaffidabile per questo difetto)
%     if acc_base < 50  % sotto 50% di accuratezza media in baseline = AE rotto
%         bonus_ia = 0;
%         info.acc_recent = acc_recent;
%         info.acc_base   = acc_base;
%         info.n_days_ae  = n_days;
%         info.valid_runs = sum(valid_mask);
%         return;
%     end
% 
%     % Calcola il calo percentuale di accuratezza (delta, non assoluto)
%     drop_perc  = max(0, (acc_base - acc_recent) / acc_base) * 100;  % 0..100%
%     bonus_ia   = min(C.IPI_IA_BONUS, drop_perc * (C.IPI_IA_BONUS / 80));  % 80% di calo = bonus pieno
% 
%     info.valid_runs = sum(valid_mask);
%     info.acc_recent = acc_recent;
%     info.acc_base   = acc_base;     % <-- nuovo campo
%     info.n_days_ae  = n_days;
%     info.valid_runs = sum(valid_mask);
%     info.acc_recent = acc_recent;
%     info.n_days_ae  = n_days;
% end

% =========================================================================
% AE HELPER STANDALONE - Calcola Bonus IA per un singolo difetto
% =========================================================================
function [bonus_ia, info] = compute_ae_bonus_for_defect(Defect, AE_Model, C)
    bonus_ia = 0;
    info = struct('valid_runs', 0, 'acc_recent', NaN, 'acc_base', NaN, 'n_days_ae', 0);

    if ~isstruct(AE_Model) || ~AE_Model.loaded || isempty(AE_Model.net), return; end

    History = Defect.History;
    n_history = length(History);
    if n_history < 2, return; end

    ae_sensors      = {'left_sensor_front', 'left_sensor_rear', ...
        'right_sensor_front', 'right_sensor_rear'};
    N_SAMPLES_AE    = 334;

    AE_acc   = nan(n_history, 1);
    AE_dates = nan(n_history, 1);

    for k = 1:n_history
        run = History(k);
        if ~isfield(run.Data, 'Filt'), continue; end
        Fd = run.Data.Filt;

        % --- FILTRO FORWARD ---
        rms_dx = 0; rms_sx = 0;
        if isfield(Fd,'right_sensor_front_lat') && ~isempty(Fd.right_sensor_front_lat)
            rms_dx = rms(double(Fd.right_sensor_front_lat));
        end
        if isfield(Fd,'left_sensor_front_lat') && ~isempty(Fd.left_sensor_front_lat)
            rms_sx = rms(double(Fd.left_sensor_front_lat));
        end
        if ~(rms_dx > rms_sx && rms_dx > 0)
            continue;   % salta back: AE non li ha mai visti
        end

        % Velocità + fattore K
        if isfield(run.Data, 'Speed') && ~isempty(run.Data.Speed) && ...
                ~isnan(run.Data.Speed) && run.Data.Speed >= 10
            v_treno = run.Data.Speed;
        else
            v_treno = AE_Model.v_ref;
        end
        if isempty(AE_Model.v_ref) || AE_Model.v_ref == 0, AE_Model.v_ref = 80; end
        K_vel = (v_treno / AE_Model.v_ref)^2;

        % INIZIALIZZAZIONE TENSORE MULTI-CANALE (1 x N_SAMPLES_AE x 4)
        multi_channel_sig = zeros(1, N_SAMPLES_AE, length(ae_sensors));
        valid_run  = true;
        for s = 1:4
            sn = ae_sensors{s};
            if isfield(Fd, sn) && ~isempty(Fd.(sn))
                sig = double(Fd.(sn));
                sig = sig(:)';
                sig = sig ./ K_vel;
                if length(sig) ~= N_SAMPLES_AE && length(sig) > 1
                    x_old = linspace(0, 1, length(sig));
                    x_new = linspace(0, 1, N_SAMPLES_AE);
                    sig = interp1(x_old, sig, x_new, 'linear', 'extrap');
                elseif length(sig) <= 1
                    sig = zeros(1, N_SAMPLES_AE);
                end
                sig = sig - mean(sig);
            else
                sig = zeros(1, N_SAMPLES_AE);
                valid_run = false;
            end
            multi_channel_sig(1, :, s) = sig;
        end
        
        if ~valid_run, continue; end
        
        % Normalizzazione e Predizione col Tensore 3D
        input_norm = (multi_channel_sig - AE_Model.mu) ./ AE_Model.sigma;
        try
            reconstructed = predict(AE_Model.net, input_norm);
        catch
            continue;
        end
        
        % Errore calcolato appiattendo matematicamente il tensore
        mse_val  = mean((input_norm(:) - reconstructed(:)).^2);
        var_orig = var(input_norm(:));
        if var_orig > 0
            r2 = 1 - (mse_val / var_orig);
            accuracy_perc = max(0, r2) * 100;
        else
            accuracy_perc = 0;
        end
        
        AE_acc(k)   = accuracy_perc;
        AE_dates(k) = datenum(run.Date);
    end
    
    % --- NUOVA LOGICA FINESTRE: recent fisso ---
    valid_mask = ~isnan(AE_acc);
    if sum(valid_mask) < 2, return; end
    
    valid_acc_v   = AE_acc(valid_mask);
    valid_dates_v = AE_dates(valid_mask);
    days_v   = floor(valid_dates_v);
    days_un  = unique(days_v);
    n_days   = length(days_un);
    history_span = days_un(end) - days_un(1);
    if history_span < C.IPI_MIN_HISTORY_DAYS, return; end
    if n_days < C.IPI_MIN_DAYS, return; end
    
    acc_daily = zeros(n_days, 1);
    for d = 1:n_days
        acc_daily(d) = mean(valid_acc_v(days_v == days_un(d)), 'omitnan');
    end
    
    cutoff_day  = days_un(end) - C.IPI_RECENT_DAYS;
    mask_recent = days_un >  cutoff_day;
    mask_base   = days_un <= cutoff_day;
    if ~any(mask_recent) || ~any(mask_base), return; end
    
    acc_recent = mean(acc_daily(mask_recent), 'omitnan');
    acc_base   = mean(acc_daily(mask_base),   'omitnan');
    
    % Gate di affidabilità: se la baseline è già bassa, l'AE non ha un buon punto zero
    if acc_base < 50 
        bonus_ia = 0;
        info.acc_recent = acc_recent;
        info.acc_base   = acc_base;
        info.n_days_ae  = n_days;
        info.valid_runs = sum(valid_mask);
        return;
    end
    
    % Calcola il calo percentuale di accuratezza
    drop_perc  = max(0, (acc_base - acc_recent) / acc_base) * 100; 
    bonus_ia   = min(C.IPI_IA_BONUS, drop_perc * (C.IPI_IA_BONUS / 80));  
    
    info.valid_runs = sum(valid_mask);
    info.acc_recent = acc_recent;
    info.acc_base   = acc_base;     
    info.n_days_ae  = n_days;
end

function a = get_max_rms(F, sensor_name, win_samples)
    if isfield(F, sensor_name)
        sig = double(F.(sensor_name));
        if ~isempty(sig) && any(sig ~= 0)
            if length(sig) >= win_samples
                rms_sig = sqrt(movmean(sig.^2, win_samples));
                a = max(rms_sig);
            else
                a = max(abs(sig));
            end
            return;
        end
    end
    a = 0;
end

function a = get_amp(F, sensor_name)
    if isfield(F, sensor_name)
        sig = double(F.(sensor_name));
        if ~isempty(sig) && any(sig ~= 0)
            a = max(abs(sig));
            return;
        end
    end
    a = 0;
end

function [psd_mean, freq_vec] = get_spectrum_psd(F, sensor_list, weights, CFG)
    win_m = 10.0; % Finestra fissa richiesta
    dx_global = CFG.SPATIAL_RES; 
    fs_global = 1 / dx_global;
    NFFT_global = round(win_m / dx_global);
    if NFFT_global < 4, NFFT_global = 4; end
    
    psd_sum = [];
    freq_vec = [];
    total_weight = 0;
    
    for s = 1:length(sensor_list)
        sn = sensor_list{s};
        w  = weights(s);
        
        if w < 1e-6 || ~isfield(F, sn), continue; end
        
        sig = double(F.(sn));
        sig = sig(:); 
        
        if isempty(sig) || length(sig) < 4, continue; end
        
        N_campioni = length(sig);
        if N_campioni > NFFT_global
            start_idx = floor((N_campioni - NFFT_global)/2) + 1;
            sig = sig(start_idx : start_idx + NFFT_global - 1);
        end
        
        [pxx, f] = periodogram(sig, hamming(length(sig)), NFFT_global, fs_global);
        
        if isempty(freq_vec)
            freq_vec = f;
            psd_sum = zeros(size(pxx));
        end
        
        if length(f) ~= length(freq_vec)
            pxx = interp1(f, pxx, freq_vec, 'linear', 0);
        end
        
        psd_sum = psd_sum + (pxx * w);
        total_weight = total_weight + w;
    end
    
    if isempty(psd_sum) || total_weight < 1e-6
        psd_mean = [];
        freq_vec = [];
    else
        psd_mean = psd_sum / total_weight;
    end
end



% =========================================================================
% HELPER FUNCTIONS
% =========================================================================
% function a = get_amp(F, sensor_name)
%     if isfield(F, sensor_name)
%         sig = double(F.(sensor_name));
%         if ~isempty(sig) && any(sig ~= 0)
%             a = max(abs(sig));
%             return;
%         end
%     end
%     a = 0;
% end

% 
% function [spectrum, freq_vec] = get_spectrum(F, sensor_list, weights, fs_space)
% % Calcola lo spettro di potenza medio pesato per ampiezza su una lista di sensori
%     spectrum = [];
%     freq_vec = [];
%     total_weight = 0;
%     spec_sum = [];
% 
%     for s = 1:length(sensor_list)
%         sn = sensor_list{s};
%         w  = weights(s);
%         if w < 1e-6 || ~isfield(F, sn), continue; end
%         sig = double(F.(sn));
%         if isempty(sig) || ~any(sig), continue; end
% 
%         N = length(sig);
%         Y = fft(sig);
%         P = abs(Y(1:floor(N/2)+1)).^2 / N;
%         f = (0:floor(N/2)) * (fs_space / N);
% 
%         if isempty(spec_sum)
%             spec_sum = zeros(size(P));
%             freq_vec = f;
%         end
%         spec_sum     = spec_sum + P * w;
%         total_weight = total_weight + w;
%     end
% 
%     if isempty(spec_sum) || total_weight < 1e-6, return; end
%     spectrum = spec_sum / total_weight;
% end

% function [spectrum, freq_vec] = get_spectrum(F, sensor_list, weights, fs_space)
%     spectrum = [];
%     freq_vec = [];
%     total_weight = 0;
%     spec_sum = [];
%     N_ref = -1;
%     f_ref = [];
% 
%     for s = 1:length(sensor_list)
%         sn = sensor_list{s};
%         w  = weights(s);
%         if w < 1e-6 || ~isfield(F, sn), continue; end
%         sig = double(F.(sn));
%         sig = sig(:); % forza vettore colonna
%         if isempty(sig) || ~any(sig), continue; end
% 
%         N = length(sig);
%         Y = fft(sig);
%         P = abs(Y(1:floor(N/2)+1)).^2 / N;
%         P = P(:); % forza vettore colonna
%         f = ((0:floor(N/2)) * (fs_space / N))';  % vettore colonna
% 
%         if N_ref < 0
%             % Primo segnale: definisce la griglia di riferimento
%             N_ref    = N;
%             f_ref    = f;
%             spec_sum = zeros(length(P), 1);
%             freq_vec = f;
%         elseif N ~= N_ref
%             % Lunghezza diversa: ricampiona P sulla griglia f_ref
%             if length(f) >= 2 && length(P) == length(f)
%                 P = interp1(f, P, f_ref, 'linear', 0);
%             else
%                 continue; % segnale troppo corto, salta
%             end
%         end
% 
%         spec_sum     = spec_sum + P * w;
%         total_weight = total_weight + w;
%     end
% 
%     if isempty(spec_sum) || total_weight < 1e-6, return; end
%     spectrum = spec_sum / total_weight;
% end

function lambda = peak_lambda_from_spectrum(spectrum, freq_vec, total_weight, CFG)
% Trova la lambda dominante dal picco dello spettro sommato nella banda di interesse
    lambda = 0;
    if isempty(spectrum) || total_weight < 1e-6, return; end

    f_min_band = 1 / CFG.L_MAX;
    f_max_band = 1 / CFG.L_MIN_QUIET;

    mask_band = (freq_vec >= f_min_band) & (freq_vec <= f_max_band);
    if ~any(mask_band), return; end

    
    spec_norm = spectrum;
    [~, idx_peak] = max(spec_norm(mask_band));
    freq_in_band  = freq_vec(mask_band);
    f_dom = freq_in_band(idx_peak);

    if f_dom > 0
        lambda = 1 / f_dom;
    end
end

function r = safe_ratio(a, b)
    if b < 1e-6
        if a < 1e-6
            r = 1.0;  % entrambi zero → simmetrico
        else
            r = 999;  % denominatore zero → infinito
        end
    else
        r = a / b;
    end
end

function label = lambda_to_label(lambda, L_giunto, L_irreg, L_deform)
    if lambda <= 0
        label = 'N/D';
    elseif lambda < L_giunto
        label = 'Corto';
    elseif lambda < L_irreg
        label = 'medio';
    elseif lambda < L_deform
        label = 'lungo';
    else
        label = 'molto lungo';
    end
end

function s = get_sign_mean(Defect, sens1, sens2)
% Restituisce il segno del valore medio al centro del segnale
% (media sui passaggi, media tra i due sensori)
    vals = [];
    for k = 1:length(Defect.History)
        run = Defect.History(k);
        if ~isfield(run.Data, 'Filt'), continue; end
        F = run.Data.Filt;
        for sn = {sens1, sens2}
            if isfield(F, sn{1})
                sig = double(F.(sn{1}));
                if ~isempty(sig)
                    mid = round(length(sig)/2);
                    half = min(5, floor(length(sig)/4));
                    vals(end+1) = mean(sig(mid-half:mid+half));
                end
            end
        end
    end
    if isempty(vals)
        s = 1;
    else
        s = sign(mean(vals));
    end
end




% function open_top_20_dashboard(h_main)
%     db_folder = h_main.DBFolder;
%     d = dir(fullfile(db_folder, 'Database_damage_*.mat'));
%     if isempty(d), msgbox('Nessun database trovato in Defect_Database'); return; end
% 
%     wb = waitbar(0, 'Scansione database e calcolo IPI globale...');
%     AllDefects = [];
% 
%     % --- Recupero Parametri Centralizzati ---
%     C = h_main.CFG; 
% 
%     % 1. Caricamento Aggregato
%     for i = 1:length(d)
%         waitbar(i/(length(d)+1), wb, sprintf('Caricamento %s...', d(i).name));
%         data = load(fullfile(db_folder, d(i).name));
%         if isfield(data, 'MASTER_DB')
%             tratta_name = strrep(strrep(d(i).name, 'Database_damage_', ''), '.mat', '');
%             temp_db = data.MASTER_DB;
%             for j = 1:length(temp_db)
%                 temp_db(j).TrattaOrigine = char(tratta_name);
%             end
% 
%             if isempty(AllDefects)
%                 AllDefects = temp_db(:);
%             else
%                 % --- FIX: PAREGGIAMENTO DINAMICO DEI CAMPI ---
%                 fields_all = fieldnames(AllDefects);
%                 fields_tmp = fieldnames(temp_db);
%                 missing_in_tmp = setdiff(fields_all, fields_tmp);
%                 for f = 1:length(missing_in_tmp)
%                     [temp_db.(missing_in_tmp{f})] = deal([]);
%                 end
%                 missing_in_all = setdiff(fields_tmp, fields_all);
%                 for f = 1:length(missing_in_all)
%                     [AllDefects.(missing_in_all{f})] = deal([]);
%                 end
%                 AllDefects = [AllDefects; temp_db(:)];
%             end
%         end
%     end
% 
%     % =========================================================
%     % 2. FILTRO MINIMO PASSAGGI STORICI (Parametrico)
%     % =========================================================
%     min_runs_req = C.IPI_MIN_RUNS; 
%     valid_mask = arrayfun(@(x) length(x.History) >= min_runs_req, AllDefects);
%     AllDefects = AllDefects(valid_mask);
% 
%     if isempty(AllDefects)
%         close(wb); msgbox(sprintf('Nessun difetto possiede il minimo richiesto di %d passaggi.', min_runs_req)); return; 
%     end
% 
%     % =========================================================
%     % 3. CALCOLO IPI PER TUTTA LA RETE (Parametrico)
%     % =========================================================
%     waitbar(length(d)/(length(d)+1), wb, 'Calcolo IPI e classificazione Rete...');
%     IPI_Scores = zeros(length(AllDefects), 1);
% 
%     for i = 1:length(AllDefects)
%         Defect = AllDefects(i);
%         n_runs = length(Defect.History);
%         ipi_final = -1;
% 
%         if n_runs >= min_runs_req
%             temp_Sev = zeros(n_runs, 1);
%             temp_Rat = zeros(n_runs, 1);
%             temp_Dat = zeros(n_runs, 1);
% 
%             for k = 1:n_runs
%                 run = Defect.History(k);
%                 temp_Dat(k) = floor(datenum(run.Date));
%                 if isfield(run.Data, 'Filt')
%                     F = run.Data.Filt;
%                     % Calcolo Severità Verticale e Ratio Laterale
%                     A_VERT_MAX = max([get_amp(F, 'left_sensor_front'), get_amp(F, 'left_sensor_rear'), ...
%                                       get_amp(F, 'right_sensor_front'), get_amp(F, 'right_sensor_rear')]);
%                     A_LAT_MAX  = max([get_amp(F, 'right_sensor_front_lat'), get_amp(F, 'right_sensor_rear_lat'), ...
%                                       get_amp(F, 'left_sensor_front_lat'), get_amp(F, 'left_sensor_rear_lat')]);
% 
%                     temp_Sev(k) = A_VERT_MAX;
%                     if A_VERT_MAX > 1e-6
%                         temp_Rat(k) = A_LAT_MAX / A_VERT_MAX;
%                     end
%                 end
%             end
% 
% 
% 
%            unique_days = unique(temp_Dat);
%             n_days = length(unique_days);
%             history_span = unique_days(end) - unique_days(1);
% 
%             % Gate: storia minima e giorni minimi
%             if history_span >= C.IPI_MIN_HISTORY_DAYS && n_days >= C.IPI_MIN_DAYS
%                 Severity_Daily = zeros(n_days, 1);
%                 Ratio_LV_Daily = zeros(n_days, 1);
%                 for d = 1:n_days
%                     mask = (temp_Dat == unique_days(d));
%                     Severity_Daily(d) = mean(temp_Sev(mask), 'omitnan');
%                     Ratio_LV_Daily(d) = mean(temp_Rat(mask), 'omitnan');
%                 end
% 
%                 % --- NUOVA LOGICA FINESTRE: recent fisso ---
%                 cutoff_day  = unique_days(end) - C.IPI_RECENT_DAYS;
%                 mask_recent = unique_days >  cutoff_day;
%                 mask_base   = unique_days <= cutoff_day;
% 
%                 if any(mask_recent) && any(mask_base)
%                     rms_base   = mean(Severity_Daily(mask_base),   'omitnan');
%                     rms_recent = mean(Severity_Daily(mask_recent), 'omitnan');
% 
%                     % 1. Punteggio Trend
%                     S_trend = 0;
%                     if rms_base > 0
%                         inc_perc = ((rms_recent - rms_base) / rms_base) * 100;
%                         S_trend = min(C.IPI_TREND_MAX, max(0, inc_perc * (C.IPI_TREND_MAX / C.IPI_TREND_SENS)));
%                     end
% 
%                     % 2. Aggravante Laterale
%                     recent_ratio_lv = mean(Ratio_LV_Daily(mask_recent), 'omitnan');
%                     Bonus_lat = min(C.IPI_LAT_BONUS, max(0, (recent_ratio_lv / C.IPI_LAT_THRESH) * C.IPI_LAT_BONUS));
% 
%                     ipi_final = round(min(100, S_trend + Bonus_lat));
%                 end
%             end
%         end
%         IPI_Scores(i) = ipi_final;
%     end
% 
%     % 4. Ordinamento (Primario: IPI decrescente | Secondario: Severità Max decrescente)
%     SortMatrix = [IPI_Scores, [AllDefects.Max_Severity]'];
%     [~, sortIdx] = sortrows(SortMatrix, [-1, -2]); 
% 
%     Top20 = AllDefects(sortIdx(1:min(20, length(sortIdx))));
%     Top20_IPI = IPI_Scores(sortIdx(1:min(20, length(sortIdx))));
% 
%     % =========================================================
%     % 5. CALCOLO EVOLUZIONE ONDA SOLO PER I TOP 20
%     % =========================================================
%     waitbar(1, wb, 'Analisi spettrale sui Top 20...');
%     for i = 1:length(Top20)
%         Defect = Top20(i);
%         n_runs = length(Defect.History);
%         lam_str = 'N/A';
% 
%         if n_runs >= min_runs_req
%             Lam_storico = zeros(n_runs, 1);
%             for k = 1:n_runs
%                 run = Defect.History(k);
%                 if isfield(run.Data, 'Filt')
%                     F = run.Data.Filt;
%                     A_SX_F = get_amp(F, 'left_sensor_front'); A_SX_R = get_amp(F, 'left_sensor_rear');
%                     A_DX_F = get_amp(F, 'right_sensor_front'); A_DX_R = get_amp(F, 'right_sensor_rear');
% 
%                     lam_val = 0;
%                     if (A_SX_F + A_SX_R) > (A_DX_F + A_DX_R)
%                         [s_val, f_val] = get_spectrum_psd(F, {'left_sensor_front','left_sensor_rear'}, [A_SX_F, A_SX_R], C);
%                         lam_val = peak_lambda_from_spectrum(s_val, f_val, A_SX_F + A_SX_R, C);
%                     else
%                         [s_val, f_val] = get_spectrum_psd(F, {'right_sensor_front','right_sensor_rear'}, [A_DX_F, A_DX_R], C);
%                         lam_val = peak_lambda_from_spectrum(s_val, f_val, A_DX_F + A_DX_R, C);
%                     end
% 
%                     if ~isempty(lam_val) && lam_val <= C.WINDOW_SIZE * 1.5
%                         Lam_storico(k) = lam_val;
%                     end
%                 end
%             end
% 
%             % Trend della lunghezza d'onda (NUOVA LOGICA: recent fisso, baseline = resto)
%             run_dates_num = arrayfun(@(r) datenum(r.Date), Defect.History);
%             cutoff_date_lam = max(run_dates_num) - C.IPI_RECENT_DAYS;
%             mask_lam_recent = run_dates_num >  cutoff_date_lam;
%             mask_lam_base   = run_dates_num <= cutoff_date_lam;
% 
%             if any(mask_lam_recent) && any(mask_lam_base)
%                 lam_base = mean(Lam_storico(mask_lam_base),   'omitnan');
%                 lam_rec  = mean(Lam_storico(mask_lam_recent), 'omitnan');
%             else
%                 lam_base = NaN; lam_rec = NaN;
%             end
% 
%             if ~isnan(lam_base) && ~isnan(lam_rec) && lam_base > 0
%                 delta_lam = lam_rec - lam_base;
%                 if delta_lam > 0.15
%                     lam_str = sprintf('<html><font color="#CC0000"><b>Allunga (+%.2fm)</b></font></html>', delta_lam);
%                 elseif delta_lam < -0.15
%                     lam_str = sprintf('<html><font color="#0000CC"><b>Accorcia (%.2fm)</b></font></html>', delta_lam);
%                 else
%                     lam_str = sprintf('<html><font color="#009900">Stabile (%+.2fm)</font></html>', delta_lam);
%                 end
%             end
%         end
%         Top20(i).EvoluzioneOndaStr = lam_str;
%         Top20(i).IPI_Score = Top20_IPI(i);
%     end
%     close(wb);
% 
%     % =========================================================
%     % 6. CREAZIONE INTERFACCIA
%     % =========================================================
%     f_top = figure('Name', 'GLOBAL TOP 20 DEFECTS (IPI RANKING)', 'NumberTitle', 'off', ...
%         'Units', 'normalized', 'Position', [0.2 0.2 0.65 0.5], 'Color', 'w', 'MenuBar', 'none');
% 
%     col_names = {'#', 'Tratta', 'PK ID', 'IPI Score', 'Max RMS [m/s^2]', 'Evoluzione Onda', 'Infrastruttura'};
% 
%     tab_data = cell(length(Top20), 7);
%     for i = 1:length(Top20)
%         tab_data{i,1} = i;
%         tab_data{i,2} = char(Top20(i).TrattaOrigine);
%         tab_data{i,3} = char(Top20(i).ID_PK);
% 
%         ipi_val = Top20(i).IPI_Score;
%         if ipi_val < 0
%             ipi_html = '<html><font color="#999999">N/A</font></html>';
%         else
%             if ipi_val >= 75, col_hex = '#CC0000';
%             elseif ipi_val >= 50, col_hex = '#FF8000';
%             elseif ipi_val >= 25, col_hex = '#E6C300';
%             else, col_hex = '#009900'; end
%             ipi_html = sprintf('<html><font color="%s"><b>%d / 100</b></font></html>', col_hex, ipi_val);
%         end
%         tab_data{i,4} = ipi_html;
%         tab_data{i,5} = Top20(i).Max_Severity;
%         tab_data{i,6} = Top20(i).EvoluzioneOndaStr;
% 
%         raw_infra = 'Linea';
%         if isfield(Top20(i), 'Infrastructure') && ~isempty(Top20(i).Infrastructure)
%             raw_infra = Top20(i).Infrastructure;
%         end
%         tab_data{i,7} = char(raw_infra);
%     end
% 
%     t = uitable('Parent', f_top, 'Data', tab_data, 'ColumnName', col_names, ...
%         'Units', 'normalized', 'Position', [0.03 0.15 0.94 0.8], 'RowName', [], ...
%         'ColumnWidth', {30, 100, 100, 90, 100, 140, 150}, ...
%         'CellSelectionCallback', @(src, evt) set(src, 'UserData', evt.Indices)); 
% 
%     btn_analyze = uicontrol('Parent', f_top, 'Style', 'pushbutton', 'String', '🔎 APRI ANALISI DETTAGLIATA', ...
%         'Units', 'normalized', 'Position', [0.3 0.03 0.4 0.08], ...
%         'BackgroundColor', [1 0.9 0.6], 'FontWeight', 'bold');
% 
%     set(btn_analyze, 'Callback', @(~,~) launch_analysis_from_top(t, Top20, h_main, btn_analyze));
% end



function open_top_20_dashboard(h_main)
    db_folder = h_main.DBFolder;
    d = dir(fullfile(db_folder, 'Database_damage_*.mat'));
    if isempty(d), msgbox('Nessun database trovato in Defect_Database'); return; end
    
    wb = waitbar(0, 'Scansione database e calcolo IPI globale...');
    AllDefects = [];
    
    % --- Recupero Parametri Centralizzati ---
    C = h_main.CFG; 

    % 1. Caricamento Aggregato
    for i = 1:length(d)
        waitbar(i/(length(d)+1), wb, sprintf('Caricamento %s...', d(i).name));
        data = load(fullfile(db_folder, d(i).name));
        if isfield(data, 'MASTER_DB')
            tratta_name = strrep(strrep(d(i).name, 'Database_damage_', ''), '.mat', '');
            temp_db = data.MASTER_DB;
            for j = 1:length(temp_db)
                temp_db(j).TrattaOrigine = char(tratta_name);
            end
            
            if isempty(AllDefects)
                AllDefects = temp_db(:);
            else
                % --- FIX: PAREGGIAMENTO DINAMICO DEI CAMPI ---
                fields_all = fieldnames(AllDefects);
                fields_tmp = fieldnames(temp_db);
                missing_in_tmp = setdiff(fields_all, fields_tmp);
                for f = 1:length(missing_in_tmp)
                    [temp_db.(missing_in_tmp{f})] = deal([]);
                end
                missing_in_all = setdiff(fields_tmp, fields_all);
                for f = 1:length(missing_in_all)
                    [AllDefects.(missing_in_all{f})] = deal([]);
                end
                AllDefects = [AllDefects; temp_db(:)];
            end
        end
    end

    % --- Filtro-giorno (se attivo nella finestra principale) anche sulla classifica globale ---
    if isfield(h_main,'DateFrom') && ~isempty(h_main.DateFrom)
        AllDefects = filter_db_by_dates(AllDefects, h_main.DateFrom, h_main.DateTo);
        if isempty(AllDefects)
            close(wb); msgbox('Nessun difetto con passaggi nell''intervallo selezionato.'); return;
        end
    end

    % =========================================================
    % 2. FILTRO MINIMO PASSAGGI STORICI
    % =========================================================
    min_runs_req = C.IPI_MIN_RUNS; 
    valid_mask = arrayfun(@(x) length(x.History) >= min_runs_req, AllDefects);
    AllDefects = AllDefects(valid_mask);
    
    if isempty(AllDefects)
        close(wb); msgbox(sprintf('Nessun difetto possiede il minimo richiesto di %d passaggi.', min_runs_req)); return; 
    end

    % =========================================================
    % 3. CALCOLO IPI COMPLETO PER TUTTA LA RETE
    % =========================================================
    waitbar(length(d)/(length(d)+1), wb, 'Calcolo IPI e classificazione Rete...');
    IPI_Scores = zeros(length(AllDefects), 1);
    
    for i = 1:length(AllDefects)
        Defect = AllDefects(i);
        n_runs = length(Defect.History);
        ipi_final = -1;
        
        if n_runs >= min_runs_req
            temp_Sev = zeros(n_runs, 1);
            temp_Rat = zeros(n_runs, 1);
            temp_Dat = zeros(n_runs, 1);
            
            for k = 1:n_runs
                run = Defect.History(k);
                temp_Dat(k) = floor(datenum(run.Date));
                if isfield(run.Data, 'Filt')
                    F = run.Data.Filt;
                    
                    % --- FIX: USO MAX RMS (0.5m) ESATTAMENTE COME NEL GLOBAL REPORT ---
                    win_samples = max(3, round(0.5 / C.SPATIAL_RES));
                    
                    A_VERT_MAX = max([get_max_rms(F, 'left_sensor_front', win_samples), ...
                                      get_max_rms(F, 'left_sensor_rear', win_samples), ...
                                      get_max_rms(F, 'right_sensor_front', win_samples), ...
                                      get_max_rms(F, 'right_sensor_rear', win_samples)]);
                                      
                    A_LAT_MAX  = max([get_max_rms(F, 'right_sensor_front_lat', win_samples), ...
                                      get_max_rms(F, 'right_sensor_rear_lat', win_samples), ...
                                      get_max_rms(F, 'left_sensor_front_lat', win_samples), ...
                                      get_max_rms(F, 'left_sensor_rear_lat', win_samples)]);
                    
                    temp_Sev(k) = A_VERT_MAX;
                    if A_VERT_MAX > 1e-6
                        temp_Rat(k) = A_LAT_MAX / A_VERT_MAX;
                    end
                end
            end
            
            unique_days = unique(temp_Dat);
            n_days = length(unique_days);
            history_span = unique_days(end) - unique_days(1);
            
            % Gate: storia minima e giorni minimi
            if history_span >= C.IPI_MIN_HISTORY_DAYS && n_days >= C.IPI_MIN_DAYS
                Severity_Daily = zeros(n_days, 1);
                Ratio_LV_Daily = zeros(n_days, 1);
                for d_idx = 1:n_days
                    mask = (temp_Dat == unique_days(d_idx));
                    Severity_Daily(d_idx) = mean(temp_Sev(mask), 'omitnan');
                    Ratio_LV_Daily(d_idx) = mean(temp_Rat(mask), 'omitnan');
                end
                
               % --- LOGICA FINESTRE: recent fisso ---
                cutoff_day  = unique_days(end) - C.IPI_RECENT_DAYS;
                mask_recent = unique_days >  cutoff_day;
                mask_base   = unique_days <= cutoff_day;
                
                if any(mask_recent) && any(mask_base)
                    rms_base   = mean(Severity_Daily(mask_base),   'omitnan');
                    rms_recent = mean(Severity_Daily(mask_recent), 'omitnan');
                    
                    % 1. VOTO BASE: TREND (Max 50 Punti)
                    S_trend = 0;
                    if rms_base > 0
                        inc_perc = ((rms_recent - rms_base) / rms_base) * 100;
                        S_trend = min(50, max(0, inc_perc * (50 / C.IPI_TREND_SENS)));
                    end
                    
                    % 2. VOTO BASE: SEVERITÀ ASSOLUTA (Max 50 Punti)
                    if rms_recent < C.IPI_SEV_THR_LOW
                        S_absolute = 0;
                    elseif rms_recent > C.IPI_SEV_THR_HIGH
                        S_absolute = 50;
                    else
                        S_absolute = 50 * (rms_recent - C.IPI_SEV_THR_LOW) / (C.IPI_SEV_THR_HIGH - C.IPI_SEV_THR_LOW);
                    end
                    
                    % 3. Aggravante Laterale
                    recent_ratio_lv = mean(Ratio_LV_Daily(mask_recent), 'omitnan');
                    Bonus_lat = min(C.IPI_LAT_BONUS, max(0, (recent_ratio_lv / C.IPI_LAT_THRESH) * C.IPI_LAT_BONUS));
                    
                    % 4. Bonus PCA
                    [Bonus_pca, ~] = compute_pca_bonus_for_defect(Defect, C);
                    
                    % IPI Finale (senza IA per il quick scan Top 20)
                    ipi_raw = S_absolute + S_trend + Bonus_lat + Bonus_pca;
                    ipi_final = round(min(100, max(0, ipi_raw)));
                end
            end
        end
        IPI_Scores(i) = ipi_final;
    end
    
    % 4. Ordinamento (Primario: IPI decrescente | Secondario: Severità Max decrescente)
    SortMatrix = [IPI_Scores, [AllDefects.Max_Severity]'];
    [~, sortIdx] = sortrows(SortMatrix, [-1, -2]); 
    
    Top20 = AllDefects(sortIdx(1:min(20, length(sortIdx))));
    Top20_IPI = IPI_Scores(sortIdx(1:min(20, length(sortIdx))));
    
    % =========================================================
    % 5. CALCOLO EVOLUZIONE ONDA SOLO PER I TOP 20
    % =========================================================
    waitbar(1, wb, 'Analisi spettrale sui Top 20...');
    for i = 1:length(Top20)
        Defect = Top20(i);
        n_runs = length(Defect.History);
        lam_str = 'N/A';
        
        if n_runs >= min_runs_req
            Lam_storico = zeros(n_runs, 1);
            for k = 1:n_runs
                run = Defect.History(k);
                if isfield(run.Data, 'Filt')
                    F = run.Data.Filt;
                    % Qui possiamo mantenere get_amp perché serve solo per scegliere il lato dominante per lo spettro
                    A_SX_F = get_amp(F, 'left_sensor_front'); A_SX_R = get_amp(F, 'left_sensor_rear');
                    A_DX_F = get_amp(F, 'right_sensor_front'); A_DX_R = get_amp(F, 'right_sensor_rear');
                    
                    lam_val = 0;
                    if (A_SX_F + A_SX_R) > (A_DX_F + A_DX_R)
                        [s_val, f_val] = get_spectrum_psd(F, {'left_sensor_front','left_sensor_rear'}, [A_SX_F, A_SX_R], C);
                        lam_val = peak_lambda_from_spectrum(s_val, f_val, A_SX_F + A_SX_R, C);
                    else
                        [s_val, f_val] = get_spectrum_psd(F, {'right_sensor_front','right_sensor_rear'}, [A_DX_F, A_DX_R], C);
                        lam_val = peak_lambda_from_spectrum(s_val, f_val, A_DX_F + A_DX_R, C);
                    end
                    
                    if ~isempty(lam_val) && lam_val <= C.WINDOW_SIZE * 1.5
                        Lam_storico(k) = lam_val;
                    end
                end
            end
            
            % Trend della lunghezza d'onda (NUOVA LOGICA: recent fisso, baseline = resto)
            run_dates_num = arrayfun(@(r) datenum(r.Date), Defect.History);
            cutoff_date_lam = max(run_dates_num) - C.IPI_RECENT_DAYS;
            mask_lam_recent = run_dates_num >  cutoff_date_lam;
            mask_lam_base   = run_dates_num <= cutoff_date_lam;
            
            if any(mask_lam_recent) && any(mask_lam_base)
                lam_base = mean(Lam_storico(mask_lam_base),   'omitnan');
                lam_rec  = mean(Lam_storico(mask_lam_recent), 'omitnan');
            else
                lam_base = NaN; lam_rec = NaN;
            end
            
            if ~isnan(lam_base) && ~isnan(lam_rec) && lam_base > 0
                delta_lam = lam_rec - lam_base;
                if delta_lam > 0.15
                    lam_str = sprintf('<html><font color="#CC0000"><b>Allunga (+%.2fm)</b></font></html>', delta_lam);
                elseif delta_lam < -0.15
                    lam_str = sprintf('<html><font color="#0000CC"><b>Accorcia (%.2fm)</b></font></html>', delta_lam);
                else
                    lam_str = sprintf('<html><font color="#009900">Stabile (%+.2fm)</font></html>', delta_lam);
                end
            end
        end
        Top20(i).EvoluzioneOndaStr = lam_str;
        Top20(i).IPI_Score = Top20_IPI(i);
    end
    close(wb);

    % =========================================================
    % 6. CREAZIONE INTERFACCIA
    % =========================================================
    f_top = figure('Name', 'GLOBAL TOP 20 DEFECTS (IPI RANKING)', 'NumberTitle', 'off', ...
        'Units', 'normalized', 'Position', [0.2 0.2 0.65 0.5], 'Color', 'w', 'MenuBar', 'none');
    
    col_names = {'#', 'Tratta', 'PK ID', 'IPI Score', 'Max RMS [m/s^2]', 'Evoluzione Onda', 'Infrastruttura'};
    
    tab_data = cell(length(Top20), 7);
    for i = 1:length(Top20)
        tab_data{i,1} = i;
        tab_data{i,2} = char(Top20(i).TrattaOrigine);
        tab_data{i,3} = char(Top20(i).ID_PK);
        
        ipi_val = Top20(i).IPI_Score;
        if ipi_val < 0
            ipi_html = '<html><font color="#999999">N/A</font></html>';
        else
            if ipi_val >= 75, col_hex = '#CC0000';
            elseif ipi_val >= 50, col_hex = '#FF8000';
            elseif ipi_val >= 25, col_hex = '#E6C300';
            else, col_hex = '#009900'; end
            ipi_html = sprintf('<html><font color="%s"><b>%d / 100</b></font></html>', col_hex, ipi_val);
        end
        tab_data{i,4} = ipi_html;
        tab_data{i,5} = Top20(i).Max_Severity;
        tab_data{i,6} = Top20(i).EvoluzioneOndaStr;
        
        raw_infra = 'Linea';
        if isfield(Top20(i), 'Infrastructure') && ~isempty(Top20(i).Infrastructure)
            raw_infra = Top20(i).Infrastructure;
        end
        tab_data{i,7} = char(raw_infra);
    end
    
    t = uitable('Parent', f_top, 'Data', tab_data, 'ColumnName', col_names, ...
        'Units', 'normalized', 'Position', [0.03 0.15 0.94 0.8], 'RowName', [], ...
        'ColumnWidth', {30, 100, 100, 90, 100, 140, 150}, ...
        'CellSelectionCallback', @(src, evt) set(src, 'UserData', evt.Indices)); 
    
    btn_analyze = uicontrol('Parent', f_top, 'Style', 'pushbutton', 'String', '🔎 APRI ANALISI DETTAGLIATA', ...
        'Units', 'normalized', 'Position', [0.3 0.03 0.4 0.08], ...
        'BackgroundColor', [1 0.9 0.6], 'FontWeight', 'bold');
        
    set(btn_analyze, 'Callback', @(~,~) launch_analysis_from_top(t, Top20, h_main, btn_analyze));
end

function launch_analysis_from_top(h_table, Top20, h_main, btn_handle)
    % Recupera gli indici salvati nello UserData dal callback
    selection_indices = get(h_table, 'UserData');
    
    % Controllo se è vuoto (nessun click fatto)
    if isempty(selection_indices)
        msgbox('Seleziona prima una riga nella tabella.', 'Attenzione', 'warn'); 
        return; 
    end
    
    % selection_indices è una matrice [riga, colonna]. Prendiamo la riga (1,1)
    row = selection_indices(1,1);
    
    % Sicurezza: controlliamo che l'indice sia valido
    if row > length(Top20) || row < 1
        return; 
    end
    
    % --- DA QUI TUTTO UGUALE A PRIMA ---
    h_mock = h_main; 
    DefectSelected = Top20(row);
    h_mock.DB = DefectSelected;
    h_mock.CurrDefectIdx = 1; 
    h_mock.CurrentTrackName = char(DefectSelected.TrattaOrigine); 
    
    guidata(btn_handle, h_mock);
    
    % Chiudiamo la finestra Top 20 (opzionale, togli se vuoi tenerla aperta)
    % close(ancestor(h_table, 'figure')); 
    
    on_open_single_analysis(btn_handle, []);

    
end


function txt = classification_datatip(event_obj, SummaryData, tipi)
    pos    = event_obj.Position;
    idx    = event_obj.DataIndex;

    try
        tipo_name = get(event_obj.Target, 'DisplayName');
        % Cerca il tipo nel nostro array
        mask = find(tipi == tipo_name);

        if ~isempty(mask) && idx <= length(mask)
            real_idx = mask(idx);
        else
            % Fallback: cerca il difetto più vicino per posizione xy
            % (utile per scatter lambda dove i punti sono pochi)
            lambdas_sx = [SummaryData.Lambda_SX];
            lambdas_dx = [SummaryData.Lambda_DX];
            amps       = [SummaryData.Amp];

            % Normalizza le distanze rispetto al range dei dati
            dx = (lambdas_sx - pos(1)) ./ (max(lambdas_sx) - min(lambdas_sx) + eps);
            dy = (lambdas_dx - pos(2)) ./ (max(lambdas_dx) - min(lambdas_dx) + eps);
            [~, real_idx] = min(dx.^2 + dy.^2);
        end

        s = SummaryData(real_idx);
        txt = {
            sprintf('PK: %s km', s.ID), ...
            sprintf('Tipo: %s', s.TipoStrutturale), ...
            sprintf('Amp: %.1f m/s²', s.Amp), ...
            sprintf('λ SX: %.2f m → %s', s.Lambda_SX, s.NaturaSpettrale_SX), ...
            sprintf('λ DX: %.2f m → %s', s.Lambda_DX, s.NaturaSpettrale_DX), ...
            sprintf('R SX/DX: %.2f  |  R Lat/Vert: %.2f', s.Ratio_SX_DX, s.Ratio_Lat_Vert)
        };
    catch
        txt = {sprintf('X: %.2f', pos(1)), sprintf('Y: %.2f', pos(2))};
    end
end



% =========================================================================
% NUOVE FUNZIONI: REPORT DI TRATTA AUTOMATICO (GLOBAL + TOP 10 + PCA)
% =========================================================================

function export_route_report_callback(DataStore, SortedIpi, DB, C, track_name, h_main)
    % Liste Nomi per allineamento LaTeX al report singolo
    nomi_profili = {'Verticale_SX', 'Verticale_DX', 'Laterale_DX', 'Laterale_SX'};
    titoli_profili = {'Verticale Sinistro', 'Verticale Destro', 'Laterale Destro', 'Laterale Sinistro'};
    nomi_psd = {'Vert_SX_Front', 'Vert_SX_Rear', 'Vert_DX_Front', 'Vert_DX_Rear', 'Lat_DX_Front', 'Lat_DX_Rear', 'Lat_SX_Front', 'Lat_SX_Rear'};
    titoli_psd = {'Vert. SX Front', 'Vert. SX Rear', 'Vert. DX Front', 'Vert. DX Rear', 'Lat. DX Front', 'Lat. DX Rear', 'Lat. SX Front', 'Lat. SX Rear'};

    folder_name = uigetdir(pwd, 'Seleziona la cartella dove salvare il Report di Tratta');
    if folder_name == 0, return; end 
    
    safe_track = strrep(track_name, '_', '-');
    export_dir = fullfile(folder_name, sprintf('Report_Tratta_%s', safe_track));
    if ~exist(export_dir, 'dir'), mkdir(export_dir); end
    
    wb = waitbar(0, 'Avvio generazione Report di Tratta...');
    
   
    % =========================================================
    % FASE 0: VISTA GLOBALE TRATTA (PANORAMICA RAW - NO FILTRI)
    % =========================================================
    waitbar(0.05, wb, 'Generazione Vista Globale RAW (Analisi Grezza)...');
    has_overview = false;
    try
        if ~isempty(SortedIpi) && ~isempty(DB)
            % Prendiamo la corsa più recente del difetto peggiore come riferimento per la tratta
            idx_worst = find(strcmp({DB.ID_PK}, SortedIpi(1).ID), 1);
            run_info = DB(idx_worst).History(end);
            fName = char(run_info.RunName);
            parts = split(fName, '_'); 
            date_folder = [parts{1} '_' parts{2}]; 
            full_path = fullfile(h_main.ParentFolder, h_main.CurrentTrackName, date_folder, [fName '.mat']);
            
            if exist(full_path, 'file')
                d_full = load(full_path, 'section_extracted');
                if isfield(d_full, 'section_extracted')
                    data_full = d_full.section_extracted;
                    L_full = length(data_full.space_neutral);
                    space_shifted = double(data_full.space_neutral(1:L_full));
                    
                    % Applicazione macroshift se presente
                    if isfield(run_info, 'MacroShift') && ~isempty(run_info.MacroShift)
                        space_shifted = space_shifted + run_info.MacroShift;
                    end
                    
                    sens_to_plot = {'left_sensor_front', 'left_sensor_rear', 'right_sensor_front', 'right_sensor_rear', 'right_sensor_front_lat', 'left_sensor_front_lat'};
                    titoli_sens = {'RAW: Vert SX Front', 'RAW: Vert SX Rear', 'RAW: Vert DX Front', 'RAW: Vert DX Rear', 'RAW: Lat DX Front', 'RAW: Lat SX Front'};
                    
                    f_over = figure('Visible', 'off', 'Position', [100, 100, 1600, 1200], 'Color', 'w');
                    n_plots = 8; 
                    step = max(1, round(0.5 / C.SPATIAL_RES)); % Decimazione
                    win_samples = max(3, round(0.5 / C.SPATIAL_RES));
                    
                    % --- PRE-ESTRAZIONE GIUNTI ---
                    % Estraiamo i giunti validi una sola volta per non pesare sul loop
                    Jt_vis = table();
                    if ~isempty(h_main.JointsMap)
                        mask_tr = strcmp(strtrim(string(h_main.JointsMap.Stations)), strtrim(string(track_name)));
                        Jt = h_main.JointsMap(mask_tr, :);
                        if height(Jt) > 0
                            % Mantieni solo i giunti che cadono dentro la lunghezza del file
                            mask_vis = Jt.Position >= space_shifted(1) & Jt.Position <= space_shifted(end);
                            Jt_vis = Jt(mask_vis, :);
                        end
                    end
                    
                    col_viola = [0.6 0.1 0.8]; % Viola brillante
                    
                    for sp = 1:6
                        ax = subplot(n_plots, 1, sp, 'Parent', f_over);
                        hold(ax, 'on'); grid(ax, 'on');
                        
                        % --- Overlay Giunti (Linee Viola) ---
                        for jm = 1:height(Jt_vis)
                            xline(ax, Jt_vis.Position(jm), '-', 'Color', col_viola, 'LineWidth', 0.8, 'Alpha', 0.5);
                        end
                        
                        if isfield(data_full, sens_to_plot{sp})
                            % SEGNALE GREZZO (SOLO RIMOZIONE DC OFFSET)
                            sig_raw = double(data_full.(sens_to_plot{sp})(1:L_full));
                            sig_raw = sig_raw - mean(sig_raw, 'omitnan');
                            
                            % Calcolo RMS per rendere visibili i picchi
                            rms_raw = sqrt(movmean(sig_raw.^2, win_samples));
                            
                            plot(ax, space_shifted(1:step:end), rms_raw(1:step:end), 'Color', [0.2 0.2 0.2], 'LineWidth', 0.6);
                            ylabel(ax, 'RMS [m/s^2]', 'FontSize', 7);
                            xlim(ax, [space_shifted(1), space_shifted(end)]);
                        end
                        
                        y_lims = get(ax, 'YLim');
                        
                        % --- Testo Giunti (Solo sul primo asse per non affollare) ---
                        if sp == 1
                            for jm = 1:height(Jt_vis)
                                % Posizionato in basso, ruotato di 90 gradi per evitare accavallamenti
                                text(ax, Jt_vis.Position(jm), y_lims(1) + (y_lims(2)-y_lims(1))*0.05, ...
                                    [' ' char(Jt_vis.Joint(jm))], 'Color', col_viola, ...
                                    'Rotation', 90, 'FontSize', 7, 'FontWeight', 'bold', 'Interpreter', 'none');
                            end
                        end
                        
                        % --- Overlay Top 10 Difetti (Linee Rosse) ---
                        for td = 1:min(10, length(SortedIpi))
                            idx_db_td = find(strcmp({DB.ID_PK}, SortedIpi(td).ID), 1);
                            if ~isempty(idx_db_td)
                                pk_pos = DB(idx_db_td).Avg_Pos;
                                xline(ax, pk_pos, 'Color', 'r', 'LineWidth', 1.2, 'Alpha', 0.6);
                                if sp == 1
                                    text(ax, pk_pos, y_lims(2)*0.9, sprintf(' #%d', td), 'Color', 'r', 'FontSize', 7, 'FontWeight', 'bold');
                                end
                            end
                        end
                        
                        title(ax, titoli_sens{sp}, 'FontSize', 9, 'FontWeight', 'bold');
                    end
                    
                    % --- Speed (Verde) ---
                    ax_spd = subplot(n_plots, 1, 7, 'Parent', f_over); hold(ax_spd, 'on'); grid(ax_spd, 'on');
                    if isfield(data_full, 'speed')
                        plot(ax_spd, space_shifted(1:step:end), double(data_full.speed(1:step:end)), 'Color', [0 0.5 0], 'LineWidth', 1.2);
                    end
                    ylabel(ax_spd, 'Vel. [km/h]', 'FontSize', 7); 
                    xlim(ax_spd, [space_shifted(1), space_shifted(end)]); 
                    
                    % --- Curve (Arancione) ---
                    ax_crv = subplot(n_plots, 1, 8, 'Parent', f_over); hold(ax_crv, 'on'); grid(ax_crv, 'on');
                    if isfield(data_full, 'curve')
                        plot(ax_crv, space_shifted(1:step:end), double(data_full.curve(1:step:end)), 'Color', [0.8 0.4 0], 'LineWidth', 1.2);
                    end
                    ylabel(ax_crv, 'Curv. [m]', 'FontSize', 7); 
                    xlabel(ax_crv, 'Posizione PK [m]', 'FontWeight', 'bold', 'FontSize', 10); 
                    xlim(ax_crv, [space_shifted(1), space_shifted(end)]);
                    
                    sgtitle(f_over, sprintf('Panoramica RAW della Tratta (Corsa: %s) - Senza Filtri', fName), 'FontWeight', 'bold', 'FontSize', 14);
                    
                    exportgraphics(f_over, fullfile(export_dir, '00_Overview_Track_RAW.png'), 'Resolution', 300);
                    close(f_over);
                    has_overview = true;
                end
            end
        end
    catch ME
        disp(['Errore Overview RAW: ' ME.message]);
    end


    % =========================================================
    % FASE 1: GRAFICI GLOBALI (Scatter con Colori Asimmetrici)
    % =========================================================
    waitbar(0.1, wb, 'Generazione Scatter Globali...');
    f_glob_scat = figure('Visible', 'off', 'Position', [100, 100, 1200, 800], 'Color', 'w');
    sgtitle(f_glob_scat, 'Contesto Globale: Max RMS (0.5m) Dati Filtrati', 'FontWeight', 'bold', 'FontSize', 14);
    
    for g = 1:4
        ds = DataStore(g);
        ax = subplot(2, 2, g, 'Parent', f_glob_scat);
        hold(ax, 'on'); grid(ax, 'on');
        
        if ~isempty(ds.Filt.MovF) && ~isempty(ds.Filt.MovR)
            vF = ds.Filt.MovF; 
            vR = ds.Filt.MovR;
            IDs = ds.Filt.DefectID;
            
            % Logica Colori Asimmetrici come nel tab principale
            ratio = vF ./ max(vR, 1e-6);
            asym_mask = (ratio > 1.5) | (ratio < 0.66);
            sym_mask = ~asym_mask;
           % Grigio per i simmetrici
            if any(sym_mask)
                scatter(ax, vF(sym_mask), vR(sym_mask), 15, [0.8 0.8 0.8], 'filled', ...
                    'MarkerFaceAlpha', 0.2, 'HandleVisibility', 'off'); % Nascosto dalla legenda
            end
            
            % Turbo Colormap per gli asimmetrici
            unique_asym_ids = unique(IDs(asym_mask));
            n_asym = length(unique_asym_ids);
            
            leg_handles = gobjects(0);
            leg_labels = {};
            
            if n_asym > 0
                cmap = turbo(max(1, n_asym));
                for k = 1:n_asym
                    uid = unique_asym_ids(k);
                    idx_mask = (IDs == uid) & asym_mask;
                    
                    % Recupera il nome della PK direttamente dal DB originale
                    pk_name = DB(uid).ID_PK;
                    
                    h_scat = scatter(ax, vF(idx_mask), vR(idx_mask), 35, cmap(k,:), 'filled', ...
                        'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.8, 'DisplayName', pk_name);
                    
                    % Salva handle e nome per la legenda
                    leg_handles(end+1) = h_scat;
                    leg_labels{end+1} = pk_name;
                end
                
                % Genera la legenda fuori dal grafico
                lgd = legend(ax, leg_handles, leg_labels, 'Location', 'bestoutside', ...
                    'Interpreter', 'none', 'FontSize', 7);
                title(lgd, 'PK Asimmetriche');
                
                % Impagina in più colonne se ci sono tanti difetti
                if n_asym > 15
                    lgd.NumColumns = ceil(n_asym / 15);
                end
            end
            mx = max([vF; vR]) * 1.1; if mx<5, mx=5; end
            plot(ax, [0 mx], [0 mx], 'k--', 'LineWidth', 1);
            axis(ax, 'square'); xlim(ax, [0 mx]); ylim(ax, [0 mx]);
        end
        xlabel(ax, 'Front [m/s^2]'); ylabel(ax, 'Rear [m/s^2]');
        title(ax, ds.Name);
    end
    exportgraphics(f_glob_scat, fullfile(export_dir, '00_Global_Scatter_RMS.png'), 'Resolution', 300);
    close(f_glob_scat);
    
    
    % =========================================================
    % FASE 2: ELABORAZIONE COMPLETA TOP 10 (PCA e Waterfalls)
    % =========================================================
    num_top = min(10, length(SortedIpi));
    for i = 1:num_top
        waitbar(0.1 + (0.7 * (i/num_top)), wb, sprintf('Elaborazione Completa Top %d di %d...', i, num_top));
        idx_db = find(strcmp({DB.ID_PK}, SortedIpi(i).ID), 1);
        if isempty(idx_db), continue; end
        Defect = DB(idx_db);
        generate_headless_daily_plots(Defect, C, export_dir, i);
    end
    
    % =========================================================
    % FASE 3: GENERAZIONE LATEX
    % =========================================================
    waitbar(0.85, wb, 'Stesura documento LaTeX...');
    tex_filename = fullfile(export_dir, sprintf('Report_Tratta_%s.tex', safe_track));
    fid = fopen(tex_filename, 'w');
    
    fprintf(fid, '\\documentclass[11pt]{article}\n');
    fprintf(fid, '\\usepackage[utf8]{inputenc}\n');
    fprintf(fid, '\\usepackage{graphicx}\n');
    fprintf(fid, '\\usepackage[a4paper, margin=1.5cm]{geometry}\n');
    fprintf(fid, '\\usepackage{float}\n'); 
    fprintf(fid, '\\usepackage{subcaption}\n'); 
    fprintf(fid, '\\usepackage{longtable}\n');
    fprintf(fid, '\\usepackage{xcolor}\n');
    fprintf(fid, '\\usepackage{amsmath}\n');
    fprintf(fid, '\\usepackage{amssymb}\n');
    
    fprintf(fid, '\\title{Report Diagnostico di Tratta: \\textbf{%s}}\n', safe_track);
    fprintf(fid, '\\author{Analisi Globale}\n');
    fprintf(fid, '\\date{\\today}\n\n');
    
    fprintf(fid, '\\begin{document}\n');
    fprintf(fid, '\\maketitle\n\n');

    if has_overview
        fprintf(fid, '\\section*{Panoramica e Contesto Spaziale (Dati RAW)}\n');
        fprintf(fid, 'Il seguente grafico illustra la risposta dinamica \\textbf{non filtrata} (RAW) dell''intera tratta. I segnali sono riportati in termini di inviluppo RMS (0.5m) calcolato direttamente sulle accelerazioni grezze, permettendo di identificare la reale energia trasmessa al carrello senza attenuazioni frequenziali.\\\\\n\n');
        fprintf(fid, 'Elementi di riferimento sovrapposti:\n');
        fprintf(fid, '\\begin{itemize}\n');
        fprintf(fid, '  \\item \\textbf{Linee Viola Sottili:} Posizione dei giunti meccanici/saldati (con relativo codice identificativo) estratti dal catasto giunti.\n');
        fprintf(fid, '  \\item \\textbf{Linee Rosse Verticali:} Ubicazione dei %d difetti top classificati per rischio di degrado.\n', min(10, length(SortedIpi)));
        fprintf(fid, '  \\item \\textbf{Profili di Base:} Velocità del treno e raggio di curvatura locale per la valutazione del contesto operativo.\n');
        fprintf(fid, '\\end{itemize}\n\n');
        
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        fprintf(fid, '\\includegraphics[width=\\textwidth]{00_Overview_Track_RAW.png}\n');
        fprintf(fid, '\\caption{Analisi RAW della tratta con identificazione giunti (grigio) e difetti critici (rosso).}\n');
        fprintf(fid, '\\end{figure}\n\n');
        fprintf(fid, '\\clearpage\n\n');
    end
    
    fprintf(fid, '\\section{Analisi Globale della Tratta}\n');

    fprintf(fid, 'Il seguente scatter plot mostra la distribuzione dell''energia (Max RMS su finestra di 0.5m) per tutti gli eventi registrati sulla tratta.\\\\\n\n');
    
    % --- LEGENDA DEGLI SCATTER NELLA PRIMA PAGINA ---
    fprintf(fid, '\\textbf{Legenda Colori (Analisi Asimmetria):}\n');
    fprintf(fid, '\\begin{itemize}\n');
    fprintf(fid, '  \\item \\textbf{Punti Grigi:} Urti simmetrici (rapporto dell''energia tra sensore Front e Rear bilanciato).\n');
    fprintf(fid, '  \\item \\textbf{Punti Colorati:} Urti asimmetrici (forte sbilanciamento tra asse anteriore e posteriore). Ad ogni difetto è assegnato un colore univoco per tracciarne la dispersione temporale.\n');
    %fprintf(fid, '  \\item \\textbf{Linee tratteggiate rosse:} 95\\textsuperscript{o} percentile della distribuzione (soglia statistica superiore).\n');
    fprintf(fid, '\\end{itemize}\n\n');

    fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
    fprintf(fid, '\\includegraphics[width=0.9\\textwidth]{00_Global_Scatter_RMS.png}\n');
    fprintf(fid, '\\caption{Scatter Plot Globale Max RMS (0.5m).}\n');
    fprintf(fid, '\\end{figure}\n\n');
    fprintf(fid, '\\clearpage\n\n');

    % --- CLASSIFICA CON SEMAFORI ---
    fprintf(fid, '\\section{Classifica Rischio Degrado (IPI) - Top %d}\n', length(SortedIpi));
    fprintf(fid, '\\begin{longtable}{|c|l|c|c|c|c|}\n');
    fprintf(fid, '\\hline\n');
    fprintf(fid, '\\textbf{Pos} & \\textbf{ID PK} & \\textbf{IPI Score} & \\textbf{Trend / Lat} & \\textbf{RMS Recente} & \\textbf{Bonus IA / PCA} \\\\\\hline\n');
    fprintf(fid, '\\endfirsthead\n');
    
    for i = 1:length(SortedIpi)
        s = SortedIpi(i); 
        safe_id = strrep(s.ID, '_', '\_'); % <-- SINGLE backslash here!
        
        % Logica Semaforo IPI (SINGLE backslashes here!)
        if s.IPI >= 75
            semaforo = '\textcolor{red}{\Large $\bullet$}';
        elseif s.IPI >= 50
            semaforo = '\textcolor{orange}{\Large $\bullet$}';
        elseif s.IPI >= 25
            semaforo = '\textcolor{olive}{\Large $\bullet$}';
        else
            semaforo = '\textcolor{green!70!black}{\Large $\bullet$}';
        end

        fprintf(fid, '%d & %s & %s \\textbf{%d/100} & %.1f / %.1f & %.1f & %.1f / %.1f \\\\\\hline\n', ...
            i, safe_id, semaforo, s.IPI, s.STrend, s.BonusLat, s.RecentRMS, s.BonusIA, s.BonusPCA);
    end
    fprintf(fid, '\\end{longtable}\n\n');

    % =========================================================
    % --- NUOVO: ESPORTAZIONE MINI-CLASSIFICHE TOP 5 IN LATEX ---
    % =========================================================
    fprintf(fid, '\\vspace{0.5cm}\n');
    fprintf(fid, '\\subsection*{Classifiche Specifiche di Severità e Deriva}\n');
    fprintf(fid, 'Oltre all''indice composito IPI, si riportano di seguito i difetti che registrano i picchi assoluti di energia (Verticale e Laterale) e quelli con la maggiore velocità di degrado recente (Trend Percentuale).\n\n');
    
    % Prepariamo i dati ordinati usando SortedIpi (che è già passato alla funzione)
    [~, sort_v] = sort([SortedIpi.MaxVert], 'descend');
    top5_v = SortedIpi(sort_v(1:min(5, end)));
    
    [~, sort_l] = sort([SortedIpi.MaxLat], 'descend');
    top5_l = SortedIpi(sort_l(1:min(5, end)));
    
    [~, sort_p] = sort([SortedIpi.IncPerc], 'descend');
    top5_p = SortedIpi(sort_p(1:min(5, end)));

    % Creazione delle 3 tabelle affiancate con minipages
    fprintf(fid, '\\begin{figure}[H]\n');
    fprintf(fid, '\\centering\n');
    
    % --- Tabella 1: Top 5 Verticale ---
    fprintf(fid, '\\begin{minipage}[t]{0.31\\textwidth}\n');
    fprintf(fid, '\\centering\n');
    fprintf(fid, '\\textbf{Top 5 Max Verticale}\\\\\n');
    fprintf(fid, '\\vspace{0.2cm}\n');
    fprintf(fid, '\\begin{tabular}{|c|c|c|}\n');
    fprintf(fid, '\\hline\n');
    fprintf(fid, '\\textbf{Pos} & \\textbf{PK} & \\textbf{RMS [$m/s^2$]} \\\\\\hline\n');
    for k = 1:length(top5_v)
        safe_id = strrep(top5_v(k).ID, '_', '\_');
        fprintf(fid, '%d & %s & %.1f \\\\\\hline\n', k, safe_id, top5_v(k).MaxVert);
    end
    fprintf(fid, '\\end{tabular}\n');
    fprintf(fid, '\\end{minipage}\\hfill\n');
    
    % --- Tabella 2: Top 5 Laterale ---
    fprintf(fid, '\\begin{minipage}[t]{0.31\\textwidth}\n');
    fprintf(fid, '\\centering\n');
    fprintf(fid, '\\textbf{Top 5 Max Laterale}\\\\\n');
    fprintf(fid, '\\vspace{0.2cm}\n');
    fprintf(fid, '\\begin{tabular}{|c|c|c|}\n');
    fprintf(fid, '\\hline\n');
    fprintf(fid, '\\textbf{Pos} & \\textbf{PK} & \\textbf{RMS [$m/s^2$]} \\\\\\hline\n');
    for k = 1:length(top5_l)
        safe_id = strrep(top5_l(k).ID, '_', '\_');
        fprintf(fid, '%d & %s & %.1f \\\\\\hline\n', k, safe_id, top5_l(k).MaxLat);
    end
    fprintf(fid, '\\end{tabular}\n');
    fprintf(fid, '\\end{minipage}\\hfill\n');
    
    % --- Tabella 3: Top 5 Peggioramento ---
    fprintf(fid, '\\begin{minipage}[t]{0.31\\textwidth}\n');
    fprintf(fid, '\\centering\n');
    fprintf(fid, '\\textbf{Top 5 Peggioramento}\\\\\n');
    fprintf(fid, '\\vspace{0.2cm}\n');
    fprintf(fid, '\\begin{tabular}{|c|c|c|}\n');
    fprintf(fid, '\\hline\n');
    fprintf(fid, '\\textbf{Pos} & \\textbf{PK} & \\textbf{Trend [\\%%]} \\\\\\hline\n');
    for k = 1:length(top5_p)
        safe_id = strrep(top5_p(k).ID, '_', '\_');
        % Aggiungiamo un '+' esplicito per i trend positivi
        if top5_p(k).IncPerc > 0
            trend_str = sprintf('+%.1f', top5_p(k).IncPerc);
        else
            trend_str = sprintf('%.1f', top5_p(k).IncPerc);
        end
        fprintf(fid, '%d & %s & %s \\\\\\hline\n', k, safe_id, trend_str);
    end
    fprintf(fid, '\\end{tabular}\n');
    fprintf(fid, '\\end{minipage}\n');
    
    fprintf(fid, '\\end{figure}\n\n');

    % --- SPIEGAZIONE DETTAGLIATA FUNZIONAMENTO IPI ---
    fprintf(fid, '\\vspace{0.5cm}\n');
    fprintf(fid, '\\section*{Metodologia di Calcolo Indice IPI}\n');
    fprintf(fid, 'L''Indice di Priorità Ispezione (IPI) è un parametro sintetico (0-100) che quantifica il rischio evolutivo del difetto, bilanciando in egual misura la componente assoluta del danno e la sua progressione temporale. La formula applicata è:\n');
    fprintf(fid, '\\begin{equation*}\n');
    fprintf(fid, 'IPI = S_{Assoluto} + S_{Trend} + B_{Lat} + B_{PCA} + B_{AI}\n');
    fprintf(fid, '\\end{equation*}\n\n');

    fprintf(fid, '\\begin{itemize}\n');
    fprintf(fid, '  \\item \\textbf{Severità Assoluta ($S_{Assoluto}$, Max 50 pts):} Valuta proattivamente il livello di energia RMS recente (ultimi %d giorni). Superati i %d m/s$^2$ vengono assegnati 50 punti, mentre sotto i %d m/s$^2$ il contributo è nullo.\n', ...
        C.IPI_RECENT_DAYS, C.IPI_SEV_THR_HIGH, C.IPI_SEV_THR_LOW);
    fprintf(fid, '  \\item \\textbf{Punteggio Trend ($S_{Trend}$, Max 50 pts):} Incremento percentuale della severità RMS recente rispetto alla baseline storica. Il punteggio massimo è raggiunto con un incremento del %d\\%%.\n', ...
        C.IPI_TREND_SENS);
    fprintf(fid, '  \\item \\textbf{Aggravante Laterale ($B_{Lat}$, Max 30 pts):} Penalità assegnata per rapporti accelerometrici Laterale/Verticale superiori a %.1f.\n', ...
        C.IPI_LAT_THRESH);
    fprintf(fid, '  \\item \\textbf{Bonus PCA ($B_{PCA}$, Max 25 pts):} Valuta l''instabilità della firma cinematica attraverso l''Analisi delle Componenti Principali e premia trend o escursioni statistiche anomale dell''errore di ricostruzione (RMSE).\n');
    fprintf(fid, '  \\item \\textbf{Bonus IA ($B_{AI}$, Max 20 pts):} Valuta la perdita di accuratezza di ricostruzione del segnale tramite un Autoencoder Neurale (Deep Learning).\n');
    fprintf(fid, '\\end{itemize}\n\n');

    fprintf(fid, '\\subsection*{Livelli di Attenzione}\n');
    fprintf(fid, '\\begin{itemize}\n');
    fprintf(fid, '  \\item \\textcolor{red}{\\textbf{Critico ($\\ge$75):}} Ispezione urgente / Intervento immediato.\n');
    fprintf(fid, '  \\item \\textcolor{orange}{\\textbf{Allerta (50-74):}} Monitoraggio ravvicinato e programmazione manutenzione.\n');
    fprintf(fid, '  \\item \\textcolor{olive}{\\textbf{Monitoraggio (25-49):}} Analisi dei trend in ufficio.\n');
    fprintf(fid, '  \\item \\textcolor{green!70!black}{\\textbf{Stabile ($<$25):}} Manutenzione ordinaria.\n');
    fprintf(fid, '\\end{itemize}\n');
    
    fprintf(fid, '\\subsection*{Requisiti di Validità}\n');
    fprintf(fid, 'Il calcolo viene eseguito solo se sono soddisfatti i requisiti minimi di sistema: almeno %d passaggi totali, una storia minima di %d giorni e almeno %d giorni di misurazioni distinte.\n\n', ...
        C.IPI_MIN_RUNS, C.IPI_MIN_HISTORY_DAYS, C.IPI_MIN_DAYS);
    
    fprintf(fid, '\\clearpage\n\n');
   % --- LOOP DETTAGLIO TOP 10 ---
    for i = 1:num_top
        s = SortedIpi(i);
        safe_id = strrep(s.ID, '_', '\_'); % <-- SINGLE backslash here too!
        
        fprintf(fid, '\\section{Posizione \\#%d: Difetto %s}\n', i, safe_id);
        
        % Executive Summary
        fprintf(fid, '\\subsection*{Executive Summary}\n');
        fprintf(fid, '\\begin{itemize}\n');
        fprintf(fid, '\\item \\textbf{Indice di Priorità Ispezione (IPI):} {\\large \\textbf{%d / 100}}\n', s.IPI);
        fprintf(fid, '\\item \\textbf{Trend Base:} %.1f \\quad \\textbf{Aggravante Lat:} %.1f \\quad \\textbf{IA/PCA:} %.1f\n', s.STrend, s.BonusLat, s.BonusIA + s.BonusPCA);
        fprintf(fid, '\\item \\textbf{RMS Recente:} %.1f m/s$^2$\n', s.RecentRMS);
        fprintf(fid, '\\end{itemize}\n\n');
        
        % 6 Segnali
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        fprintf(fid, '\\includegraphics[width=\\textwidth]{TOP%02d_0_Max_Run_Signals.png}\n', i);
        fprintf(fid, '\\caption{Segnali cinematici del passaggio a massima severità.}\n');
        fprintf(fid, '\\end{figure}\n\n');
        fprintf(fid, '\\clearpage\n\n');

       
        % --- SEZIONE PCA ---
        f_pca_anom = sprintf('TOP%02d_3_PCA_Anom.png', i);
        f_pca_scree = sprintf('TOP%02d_3_PCA_Scree.png', i);
        f_pca_mani = sprintf('TOP%02d_3_PCA_Mani.png', i);
        f_pca_sig = sprintf('TOP%02d_3_PCA_Sig.png', i);

        if exist(fullfile(export_dir, f_pca_anom), 'file')
            fprintf(fid, '\\subsection*{Analisi delle Componenti Principali (Channel-Space PCA)}\n');
            fprintf(fid, 'L''algoritmo implementa una PCA spazialmente parallela (Channel-Space PCA). Riducendo le matrici in un sottospazio di $k=2$ componenti, estrae la firma cinematica di base e valuta il disallineamento geometrico (RMSE) dell''urto.\\\\\n\n');
            
            fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s}\n\\caption{Anomaly Score (RMSE)}\\end{subfigure}\\hfill\n', f_pca_anom);
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s}\n\\caption{Scree Plot (Varianza)}\\end{subfigure}\\\\[0.4cm]\n', f_pca_scree);
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s}\n\\caption{Evoluzione PC1 e PC2 vs Tempo}\\end{subfigure}\\hfill\n', f_pca_mani);
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{%s}\n\\caption{Evoluzione Firma Media per Sensore}\\end{subfigure}\n', f_pca_sig);
            fprintf(fid, '\\caption{Risultati dell''analisi PCA sul difetto.}\n');
            fprintf(fid, '\\end{figure}\n\n');
            
            fprintf(fid, '\\textbf{Analisi Matematica e Guida alla Lettura:}\n');
            fprintf(fid, '\\begin{itemize}\n');
            
            fprintf(fid, '  \\item \\textbf{(a) Anomaly Score (RMSE):} Calcolato proiettando le misurazioni nello spazio dei residui $\\mathbf{R}$. Per ogni passaggio $i$, si valuta lo scostamento geometrico rispetto ai $C=6$ canali sensore:\n');
            fprintf(fid, '  \\[ RMSE_i = \\sqrt{\\frac{1}{M} \\sum_{m=1}^{M} \\left( \\frac{1}{C} \\sum_{c=1}^{C} R_{i,m,c}^2 \\right)} \\]\n');
            fprintf(fid, '  Un trend in crescita o la presenza di picchi oltre la soglia statistica ($\\mu_{RMSE} + 2\\sigma_{RMSE}$) indica un''evoluzione anomala dell''urto o un disassamento meccanico.\n\n');
            
            fprintf(fid, '  \\item \\textbf{(b) Scree Plot (Varianza):} Rappresenta la percentuale cumulativa di varianza spiegata $EV_k$ dalle componenti principali estratte nello spazio parallelo dei canali. Una varianza spiegata molto bassa indica un urto instabile ad alta dispersione energetica spaziale.\n\n');
            
            fprintf(fid, '  \\item \\textbf{(c) Evoluzione PC1 e PC2 vs Tempo:} Mostra l''andamento nel tempo delle prime due componenti principali (i marcatori opachi indicano le medie settimanali). Una forte deriva (trend crescente o decrescente) dei punteggi indica una mutazione progressiva della morfologia dell''onda.\n\n');
            
            fprintf(fid, '  \\item \\textbf{(d) Firma Media per Sensore:} Sovrapposizione delle forme d''onda medie suddivise per blocchi temporali continui. Mostra come il difetto evolve (in ampiezza o estensione spaziale) isolando il comportamento fisico per ciascun punto di misura del carrello.\n');
            
            fprintf(fid, '\\end{itemize}\n\n');
            
            fprintf(fid, '\\clearpage\n\n');
        end
        
       % Indicatori Globali (3x3, Lat, Lam)
        fprintf(fid, '\\subsection*{Indicatori Diagnostici (Media Giornaliera)}\n');
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{TOP%02d_2_Giornaliera_C_Matrice3x3.png}\n\\caption{Matrice 3x3 Simmetria}\\end{subfigure}\\hfill\n', i);
        fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{TOP%02d_2_Giornaliera_D_RatioLat.png}\n\\caption{Rapporto Laterale/Verticale}\\end{subfigure}\\\\[0.4cm]\n', i);
        fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\\includegraphics[width=\\textwidth]{TOP%02d_2_Giornaliera_E_Lambda.png}\n\\caption{Evoluzione Lunghezza d''Onda}\\end{subfigure}\n', i);
        fprintf(fid, '\\caption{Indicatori evolutivi globali per il difetto.}\n');
        fprintf(fid, '\\end{figure}\n\n');
        fprintf(fid, '\\clearpage\n\n');
        
        % Waterfall 3D
        fprintf(fid, '\\subsection*{Evoluzione Profilo Spaziale 3D (Max RMS)}\n');
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        for idx_prof = 1:4
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\n');
            fprintf(fid, '\\includegraphics[width=\\textwidth]{TOP%02d_2_Giornaliera_A_Profilo_%s.png}\n', i, nomi_profili{idx_prof});
            fprintf(fid, '\\caption{Waterfall %s}\n', titoli_profili{idx_prof});
            fprintf(fid, '\\end{subfigure}\n');
            if mod(idx_prof, 2) == 1, fprintf(fid, '\\hfill\n');
            elseif idx_prof == 2, fprintf(fid, '\n\n\\vspace{0.4cm}\n\n'); end
        end
        fprintf(fid, '\\caption{Evoluzione della forma d''onda spaziale per i 4 gruppi sensori.}\n');
        fprintf(fid, '\\end{figure}\n\n');
        fprintf(fid, '\\clearpage\n\n');
        
        % PSD Verticali
        fprintf(fid, '\\subsection*{Evoluzione Spettrale (PSD 3D) - Sensori Verticali}\n');
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        for idx_psd = 1:4
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\n');
            fprintf(fid, '\\includegraphics[width=\\textwidth]{TOP%02d_2_Giornaliera_B_PSD_%d_%s.png}\n', i, idx_psd, nomi_psd{idx_psd});
            fprintf(fid, '\\caption{PSD: %s}\n', titoli_psd{idx_psd});
            fprintf(fid, '\\end{subfigure}\n');
            if mod(idx_psd, 2) == 1, fprintf(fid, '\\hfill\n');
            elseif idx_psd == 2, fprintf(fid, '\n\n\\vspace{0.4cm}\n\n'); end
        end
        fprintf(fid, '\\caption{Contenuto in frequenza spaziale per i sensori verticali.}\n');
        fprintf(fid, '\\end{figure}\n\n');
        
        % PSD Laterali
        fprintf(fid, '\\subsection*{Evoluzione Spettrale (PSD 3D) - Sensori Laterali}\n');
        fprintf(fid, '\\begin{figure}[H]\n\\centering\n');
        for idx_psd = 5:8
            fprintf(fid, '\\begin{subfigure}[b]{0.48\\textwidth}\n\\centering\n');
            fprintf(fid, '\\includegraphics[width=\\textwidth]{TOP%02d_2_Giornaliera_B_PSD_%d_%s.png}\n', i, idx_psd, nomi_psd{idx_psd});
            fprintf(fid, '\\caption{PSD: %s}\n', titoli_psd{idx_psd});
            fprintf(fid, '\\end{subfigure}\n');
            if mod(idx_psd, 2) == 1, fprintf(fid, '\\hfill\n');
            elseif idx_psd == 6, fprintf(fid, '\n\n\\vspace{0.4cm}\n\n'); end
        end
        fprintf(fid, '\\caption{Contenuto in frequenza spaziale per i sensori laterali.}\n');
        fprintf(fid, '\\end{figure}\n\n');
        
        fprintf(fid, '\\clearpage\n\n');
    end
    
    fprintf(fid, '\\end{document}\n');
    fclose(fid);
    
    % =========================================================
    % FASE 4: COMPILAZIONE PDF
    % =========================================================
    waitbar(0.95, wb, 'Compilazione PDF...');
    old_dir = cd(export_dir); 
    try
        [status, cmdout] = system(sprintf('pdflatex -interaction=nonstopmode "Report_Tratta_%s.tex"', safe_track));
        cd(old_dir); 
        if status == 0
            close(wb);
            msgbox(sprintf('Report di Tratta generato con successo in:\n%s', export_dir), 'PDF Pronto');
            try winopen(fullfile(export_dir, sprintf('Report_Tratta_%s.pdf', safe_track))); catch, end
        else
            close(wb);
            errordlg('Immagini esportate, ma errore in compilazione LaTeX. Controlla la Command Window.', 'Errore Compilazione');
            disp(cmdout);
        end
    catch ME
        cd(old_dir); close(wb);
        errordlg(['Impossibile lanciare pdflatex. Dettagli: ', ME.message]);
    end
end

% --- Funzione Headless per estrarre TUTTE le metriche dei Top 10 ---
function generate_headless_daily_plots(Defect, C, export_dir, rank_idx)
    History = Defect.History;
    n_runs = length(History);
    if n_runs == 0, return; end
    
    dates_num = zeros(n_runs, 1); AllAmps = zeros(n_runs, 8); Lambda_All = zeros(n_runs, 8);
    win_samples_base = max(3, round(0.5 / C.SPATIAL_RES));
    NFFT_val = max(4, round(10.0 / C.SPATIAL_RES)); fs_space = 1 / C.SPATIAL_RES;
    
    sens_list = {'left_sensor_front', 'left_sensor_rear', 'right_sensor_front', 'right_sensor_rear', ...
                 'right_sensor_front_lat', 'right_sensor_rear_lat', 'left_sensor_front_lat', 'left_sensor_rear_lat'};
    
    max_global_amp = 0; max_run_idx = 1;
    
    for i = 1:n_runs
        run = History(i);
        dates_num(i) = datenum(run.Date);
        if isfield(run.Data, 'Filt')
            for s = 1:8
                sn = sens_list{s};
                if isfield(run.Data.Filt, sn)
                    sig = double(run.Data.Filt.(sn)); sig = sig(:);
                    if isempty(sig), continue; end
                    
                    if length(sig) >= win_samples_base
                        rms_sig = sqrt(movmean(sig.^2, win_samples_base));
                        AllAmps(i, s) = max(rms_sig);
                    else
                        AllAmps(i, s) = max(abs(sig));
                    end
                    
                    if length(sig) >= 4 
                        [pxx, f] = periodogram(sig, hamming(length(sig)), NFFT_val, fs_space);
                        [~, p_idx] = max(pxx);
                        if f(p_idx) > 0.05, Lambda_All(i, s) = 1/f(p_idx); end
                    end
                end
            end
        end
        run_max_amp = max(AllAmps(i, 1:4));
        if run_max_amp > max_global_amp, max_global_amp = run_max_amp; max_run_idx = i; end
    end
    
    Ratio_SX_DX = (AllAmps(:,1) + AllAmps(:,2)) ./ max(AllAmps(:,3) + AllAmps(:,4), 1e-6);
    Ratio_FR    = (AllAmps(:,1) + AllAmps(:,3)) ./ max(AllAmps(:,2) + AllAmps(:,4), 1e-6);
    Ratio_LV    = max(AllAmps(:,5:8), [], 2) ./ max(max(AllAmps(:,1:4), [], 2), 1e-6);
    
    days_floor = floor(dates_num);
    unique_days = unique(days_floor);
    n_days = length(unique_days);
    
    avg_Ratio_SX_DX = zeros(n_days, 1); avg_Ratio_FR = zeros(n_days, 1);
    avg_Ratio_LV = zeros(n_days, 1); avg_Lambda_All = zeros(n_days, 8);
    for k = 1:n_days
        mask = (days_floor == unique_days(k));
        avg_Ratio_SX_DX(k) = mean(Ratio_SX_DX(mask), 'omitnan');
        avg_Ratio_FR(k)    = mean(Ratio_FR(mask), 'omitnan');
        avg_Ratio_LV(k)    = mean(Ratio_LV(mask), 'omitnan');
        avg_Lambda_All(k,:)= mean(Lambda_All(mask,:), 1, 'omitnan');
    end
    
    f_temp = figure('Visible', 'off', 'Position', [100, 100, 800, 600], 'Color', 'w');
    
    % --- 1. FIRMA RUN MASSIMA ---
    run_max = History(max_run_idx);
    
    % --- NUOVA LOGICA: Trova il sensore laterale attivo ---
    rms_dx = 0; rms_sx = 0;
    if isfield(run_max.Data, 'Filt')
        if isfield(run_max.Data.Filt, 'right_sensor_front_lat') && ~isempty(run_max.Data.Filt.right_sensor_front_lat)
            rms_dx = rms(double(run_max.Data.Filt.right_sensor_front_lat));
        end
        if isfield(run_max.Data.Filt, 'left_sensor_front_lat') && ~isempty(run_max.Data.Filt.left_sensor_front_lat)
            rms_sx = rms(double(run_max.Data.Filt.left_sensor_front_lat));
        end
    end

    if rms_sx > rms_dx
        lat_f = 'left_sensor_front_lat'; lat_r = 'left_sensor_rear_lat';
    else
        lat_f = 'right_sensor_front_lat'; lat_r = 'right_sensor_rear_lat';
    end

    active_sig_fields = {'left_sensor_front', 'left_sensor_rear', 'right_sensor_front', 'right_sensor_rear', lat_f, lat_r};

    for s_idx = 1:6
        ax_s = subplot(3, 2, s_idx, 'Parent', f_temp); hold(ax_s, 'on'); grid(ax_s, 'on');
        field = active_sig_fields{s_idx};
        if isfield(run_max.Data, 'Filt') && isfield(run_max.Data.Filt, field)
            plot(ax_s, run_max.Data.RelativeAxis, run_max.Data.Filt.(field), 'Color', [0 0.4 0.8]);
        end
        title(ax_s, strrep(field, '_', ' '));

        % --- AGGIUNTA ETICHETTE E UNITÀ DI MISURA ---
        xlabel(ax_s, 'Posizione [m]', 'FontSize', 8);
        ylabel(ax_s, 'Acc. [m/s^2]', 'FontSize', 8, 'Interpreter', 'tex');
    end
    sgtitle(f_temp, sprintf('Firma Run Massima (%.1f m/s^2)', max_global_amp), 'FontWeight', 'bold');
    exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_0_Max_Run_Signals.png', rank_idx)), 'Resolution', 300);
   % --- 2. MATRICE 3X3 CON LEGENDA TEMPORALE ---
    clf(f_temp); ax = axes('Parent', f_temp); hold(ax, 'on'); grid(ax, 'on');
    
    % Disegno dei punti
    scatter(ax, avg_Ratio_SX_DX, avg_Ratio_FR, 60, unique_days, 'filled', 'MarkerEdgeColor', 'k');
    
    % Soglie
    xline(ax, 2.0, 'r--'); xline(ax, 0.5, 'r--'); 
    yline(ax, 2.0, 'b--'); yline(ax, 0.5, 'b--');
    
    % Scale e Colormap
    set(ax, 'XScale', 'log', 'YScale', 'log'); 
    colormap(ax, parula);
    
    % --- AGGIUNTA LEGENDA (COLORBAR) ---
    cb = colorbar(ax);
    datetick(cb, 'y', 'dd/mm', 'keepticks'); % Formatta la legenda con le date
    ylabel(cb, 'Evoluzione Temporale', 'FontWeight', 'bold');
    
    % --- AGGIUNTA ETICHETTA "ATTUALE" ---
    if ~isempty(avg_Ratio_SX_DX)
        text(ax, avg_Ratio_SX_DX(end), avg_Ratio_FR(end), '  \leftarrow ATTUALE', ...
            'Color', 'r', 'FontWeight', 'bold', 'FontSize', 9);
    end

    xlabel(ax, 'Ratio Laterale (SX/DX)'); 
    ylabel(ax, 'Ratio Longitudinale (Front/Rear)'); 
    title(ax, 'Matrice 3x3 (Giornaliera)');
    
    % Esportazione
    exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_2_Giornaliera_C_Matrice3x3.png', rank_idx)), 'Resolution', 300);
    
    % --- 3. RATIO LATERALE ---
    clf(f_temp); ax = axes('Parent', f_temp); hold(ax, 'on'); grid(ax, 'on');
    plot(ax, unique_days, avg_Ratio_LV, '-ok', 'MarkerFaceColor', 'y', 'LineWidth', 2);
    yline(ax, 0.6, 'r-', 'LineWidth', 2); datetick(ax, 'x', 'dd/mm/yy', 'keepticks');
    xlabel(ax, 'Data'); ylabel(ax, 'Ratio Lat/Vert'); title(ax, 'Evoluzione Laterale');
    exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_2_Giornaliera_D_RatioLat.png', rank_idx)), 'Resolution', 300);
    
    % --- 4. LAMBDA ---
    clf(f_temp); ax = axes('Parent', f_temp); hold(ax, 'on'); grid(ax, 'on');
    colors = lines(4);
    h_plots = gobjects(4,1);
    sensor_names = {'SX Front', 'SX Rear', 'DX Front', 'DX Rear'};
    for s = 1:4
        h_plots(s) = plot(ax, unique_days, avg_Lambda_All(:, s), '-o', 'Color', colors(s,:), 'MarkerFaceColor', colors(s,:)); 
    end
    datetick(ax, 'x', 'dd/mm/yy', 'keepticks'); 
    xlabel(ax, 'Data'); ylabel(ax, '\lambda [m]'); 
    title(ax, 'Evoluzione Lunghezza d''Onda (Verticali)');
    legend(ax, h_plots, sensor_names, 'Location', 'northeast', 'FontSize', 7); % <--- AGGIUNTO

    exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_2_Giornaliera_E_Lambda.png', rank_idx)), 'Resolution', 300);

    % =========================================================================
    % 5. ANALISI PCA (HEADLESS)
    % =========================================================================
    [idx_fwd, idx_bwd] = sort_runs_by_direction(History);
    use_fwd = sum(idx_fwd) >= sum(idx_bwd);
    if use_fwd, run_idx_pca = find(idx_fwd); dir_label = 'Forward';
    else,       run_idx_pca = find(idx_bwd); dir_label = 'Backward'; end

    if length(run_idx_pca) >= C.IPI_PCA_MIN_RUNS
        N_GRID = 333; n_chan = 6;
        x_grid = linspace(-C.WINDOW_SIZE, C.WINDOW_SIZE, N_GRID);
        win_samples_pca = max(3, round(0.5 / C.SPATIAL_RES));
        
        if use_fwd
            chan_fields = {'left_sensor_front', 'right_sensor_front', 'right_sensor_front_lat', ...
                           'left_sensor_rear', 'right_sensor_rear', 'right_sensor_rear_lat'};
        else
            chan_fields = {'left_sensor_front', 'right_sensor_front', 'left_sensor_front_lat', ...
                           'left_sensor_rear', 'right_sensor_rear', 'left_sensor_rear_lat'};
        end
        ch_labels = {'V SX-F','V DX-F','Lat-F','V SX-R','V DX-R','Lat-R'};
        
        X_pca = nan(length(run_idx_pca), n_chan * N_GRID);
        dates_pca = nan(length(run_idx_pca), 1);
        amps_pca = nan(length(run_idx_pca), 1);
        valid_pca = false(length(run_idx_pca), 1);
        
        for pk = 1:length(run_idx_pca)
            r_i = History(run_idx_pca(pk));
            if ~isfield(r_i.Data, 'Filt') || ~isfield(r_i.Data, 'RelativeAxis'), continue; end
            ax_src = double(r_i.Data.RelativeAxis(:));
            if ~issorted(ax_src) || any(~isfinite(ax_src)), continue; end
            Fd = r_i.Data.Filt;
            row_pca = nan(1, n_chan * N_GRID);
            row_ok = true;
            for c = 1:n_chan
                fn = chan_fields{c};
                if ~isfield(Fd, fn) || isempty(Fd.(fn)), row_ok=false; break; end
                sig = double(Fd.(fn)(:));
                if length(sig) ~= length(ax_src) || numel(sig)<10, row_ok=false; break; end
                env = sqrt(movmean(sig.^2, win_samples_pca));
                env_g = interp1(ax_src, env, x_grid, 'linear', NaN);
                if any(~isfinite(env_g)), row_ok=false; break; end
                row_pca((c-1)*N_GRID + 1 : c*N_GRID) = env_g;
            end
            if row_ok
                X_pca(pk, :) = row_pca; dates_pca(pk) = datenum(r_i.Date);
                amps_pca(pk) = r_i.Amp; valid_pca(pk) = true;
            end
        end
        
       
        X_pca = X_pca(valid_pca, :); dates_pca = dates_pca(valid_pca); amps_pca = amps_pca(valid_pca);
        if size(X_pca, 1) >= C.IPI_PCA_MIN_RUNS
            try
                n_valid_pca = size(X_pca, 1);
                
                % --- VERA CHANNEL-SPACE PCA (Parallela a 6 Componenti) ---
                Nrows = n_valid_pca * N_GRID;
                Xpar  = zeros(Nrows, n_chan); % Righe: (passaggio x posizione) | Colonne: Canale
                run_id = zeros(Nrows, 1);
                
                for r = 1:n_valid_pca
                    base = (r-1)*N_GRID;
                    run_id(base+1 : base+N_GRID) = r;
                    for c = 1:n_chan
                        cols = (c-1)*N_GRID + 1 : c*N_GRID;
                        Xpar(base+1 : base+N_GRID, c) = X_pca(r, cols).';
                    end
                end

                % Standardizzazione per-canale coerente
                mu_ch = mean(Xpar, 1);
                sg_ch = std(Xpar, 0, 1);
                sg_ch(sg_ch < 1e-9) = 1;
                Xpar_z = (Xpar - mu_ch) ./ sg_ch;
                
                [coeffs, scores_full, ~, ~, explained, mu_pca] = pca(Xpar_z, 'Economy', true);
                
                % Ordinamento cronologico
                [dates_pca, ord] = sort(dates_pca);
                amps_pca = amps_pca(ord);
                X_pca = X_pca(ord, :); % Manteniamo l'originale ordinato
                
                % Calcolo esatto del Residuo e dell'RMSE geometrico parallelo
                k_use = min(2, size(coeffs, 2));
                resid_z  = scores_full(:, k_use+1:end) * coeffs(:, k_use+1:end)';
                se_row   = mean(resid_z.^2, 2);
                rmse_run = sqrt(accumarray(run_id, se_row, [n_valid_pca 1], @mean));
                rmse_vec = rmse_run(ord); % Ordinato cronologicamente
                
                % Scores per il manifold (media per passaggio)
                P = size(scores_full, 2);
                scores_run = zeros(n_valid_pca, P);
                for j = 1:P
                    scores_run(:, j) = accumarray(run_id, scores_full(:, j), [n_valid_pca 1], @mean);
                end
                scores = scores_run(ord, :); % Ordinato cronologicamente
                
                % Ricostruzione destandardizzata per le firme
                recon_chan = (scores_full(:, 1:k_use) * coeffs(:, 1:k_use)' + mu_pca) .* sg_ch + mu_ch;
                X_orig_un = X_pca; % L'originale non era scalato
                X_rec_un = nan(n_valid_pca, n_chan * N_GRID);
                
                for r = 1:n_valid_pca
                    orig_r = ord(r); % Indice originale prima del sort
                    base = (orig_r-1)*N_GRID;
                    for c = 1:n_chan
                        cols = (c-1)*N_GRID + 1 : c*N_GRID;
                        X_rec_un(r, cols) = recon_chan(base+1 : base+N_GRID, c).';
                    end
                end
                
               
               % Plot PCA Anom (Arricchito)
                clf(f_temp); ax = axes('Parent', f_temp); hold(ax, 'on'); grid(ax, 'on');
                scatter(ax, dates_pca, rmse_vec, 35, amps_pca, 'filled', 'MarkerEdgeColor', 'k');
                
                % Aggiunta Trend lineare e Media mobile
                t_norm = dates_pca - dates_pca(1);
                p_fit  = polyfit(t_norm, rmse_vec, 1);
                h_trend = plot(ax, dates_pca, polyval(p_fit, t_norm), 'r-', 'LineWidth', 2);
                
                w_win = max(3, round(length(dates_pca)/15));
                h_mov = plot(ax, dates_pca, movmean(rmse_vec, w_win), 'k-', 'LineWidth', 1.5);
                
                yline(ax, mean(rmse_vec) + 2*std(rmse_vec), '--r', '\mu + 2\sigma', 'LineWidth', 1.2);
                yline(ax, mean(rmse_vec), ':k', '\mu', 'LineWidth', 1);
                datetick(ax, 'x', 'dd/mm/yy', 'keeplimits');
                title(ax, sprintf('Anomaly Score (k=%d, trend=%+.5f/giorno) - %s', k_use, p_fit(1), dir_label));
                xlabel(ax, 'Data'); ylabel(ax, 'RMSE ricostruzione');
                
                cb = colorbar(ax); 
                cb.Label.String = 'Max RMS 0.5m tra i sensori [m/s^2]';
                cb.Label.Interpreter = 'tex';
                legend(ax, [h_trend, h_mov], {'Trend lineare', sprintf('Media mobile w=%d', w_win)}, 'Location', 'best');
                
                exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_3_PCA_Anom.png', rank_idx)), 'Resolution', 300);
                
                % Plot PCA Scree
                clf(f_temp); ax = axes('Parent', f_temp); hold(ax, 'on'); grid(ax, 'on');
                k_show = min(15, numel(explained));
                bar(ax, 1:k_show, explained(1:k_show), 'FaceColor', [0.3 0.5 0.8]);
                plot(ax, 1:k_show, cumsum(explained(1:k_show)), 'r-o', 'LineWidth', 1.5);
                yline(ax, 95, '--k', '95%'); xline(ax, k_use, ':r', sprintf('k=%d', k_use), 'LineWidth', 1.5);
                title(ax, 'Scree Plot (Varianza)'); xlabel(ax, 'Componenti'); ylabel(ax, '% Varianza');
                exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_3_PCA_Scree.png', rank_idx)), 'Resolution', 300);
                
               
               
                % Plot PCA: PC1 e PC2 vs Tempo
                clf(f_temp); ax = axes('Parent', f_temp); hold(ax, 'on'); grid(ax, 'on');
                days_t = dates_pca - dates_pca(1);
                
                % Calcolo Centroidi Settimanali
                WEEK_BIN  = 7;
                week_id   = floor(days_t / WEEK_BIN);
                uw        = unique(week_id);
                n_weeks   = length(uw);
                cent_pc1  = zeros(n_weeks, 1); cent_pc2  = zeros(n_weeks, 1); cent_date = zeros(n_weeks, 1);
                for w = 1:n_weeks
                    mw = (week_id == uw(w));
                    cent_pc1(w) = mean(scores(mw, 1));
                    cent_pc2(w) = mean(scores(mw, 2));
                    cent_date(w) = mean(dates_pca(mw));
                end
                
                % Disegno punti singoli (sfondo semi-trasparente)
                scatter(ax, dates_pca, scores(:,1), 25, [0 0.4 0.8], 'filled', 'MarkerFaceAlpha', 0.25, 'MarkerEdgeAlpha', 0, 'HandleVisibility', 'off');
                scatter(ax, dates_pca, scores(:,2), 25, [0.8 0.4 0], 'filled', 'MarkerFaceAlpha', 0.25, 'MarkerEdgeAlpha', 0, 'HandleVisibility', 'off');
                
                % Disegno linee centroidi settimanali
                plot(ax, cent_date, cent_pc1, '-o', 'Color', [0 0.4 0.8], 'LineWidth', 2, 'MarkerFaceColor', [0 0.4 0.8], 'DisplayName', sprintf('PC1 (%.1f%%)', explained(1)));
                plot(ax, cent_date, cent_pc2, '-s', 'Color', [0.8 0.4 0], 'LineWidth', 2, 'MarkerFaceColor', [0.8 0.4 0], 'DisplayName', sprintf('PC2 (%.1f%%)', explained(2)));
                
                % Formattazione assi
                datetick(ax, 'x', 'dd/mm/yy', 'keepticks', 'keeplimits');
                xlabel(ax, 'Data', 'FontWeight', 'bold'); 
                ylabel(ax, 'Score PCA', 'FontWeight', 'bold');
                title(ax, sprintf('Evoluzione Componenti Principali nel Tempo (%d sett)', n_weeks), 'FontWeight', 'bold');
                legend(ax, 'Location', 'best');
                
                exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_3_PCA_Mani.png', rank_idx)), 'Resolution', 300);

            % Plot PCA Sig (Fasi Temporali 2x3 Grid)
                clf(f_temp);
                m_l = 0.06; m_b = 0.08; g_x = 0.04; g_y = 0.12;
                a_w = (1 - 2*m_l - 2*g_x)/3;
                a_h = (0.85 - m_b - g_y)/2;
                
                % Raggruppamento Fasi Bisettimanali per il plot
                bin_time = floor((dates_pca - min(dates_pca)) / 14);
                [~, ~, phase] = unique(bin_time);
                P = max(phase);
                tt_col  = linspace(0, 1, max(P,2))'; tt_col = tt_col(1:P);
                pcol = (1-tt_col).*[0 0.45 0.74] + tt_col.*[0.85 0.1 0.1];
                
                % --- NUOVO: Preparazione etichette per la legenda (Data di inizio fase) ---
                phase_labels = cell(1, P);
                for p_i = 1:P
                    mask_p = (phase == p_i);
                    if any(mask_p)
                        phase_labels{p_i} = datestr(min(dates_pca(mask_p)), 'dd/mm/yy');
                    end
                end
                
                max_y_sig = 0;
                for c = 1:n_chan
                    cols = (c-1)*N_GRID + 1 : c*N_GRID;
                    max_y_sig = max(max_y_sig, max(mean(X_orig_un(:, cols), 1) + std(X_orig_un(:, cols), 0, 1)));
                end
                
                for c = 1:n_chan
                    row_ax = floor((c-1)/3); col_ax = mod(c-1, 3);
                    ax_s = axes('Parent', f_temp, 'Position', [m_l + col_ax*(a_w+g_x), 0.85 - a_h - row_ax*(a_h + g_y), a_w, a_h]);
                    hold(ax_s, 'on'); grid(ax_s, 'on');
                    
                    cols = (c-1)*N_GRID + 1 : c*N_GRID;
                    for p_i = 1:P
                        mask_p = (phase == p_i);
                        if ~any(mask_p), continue; end
                        sub_rows = X_orig_un(mask_p, cols);
                        mu_sig = mean(sub_rows, 1);
                        sd_sig = std(sub_rows, 0, 1);
                        fill(ax_s, [x_grid, fliplr(x_grid)], [mu_sig + sd_sig, fliplr(mu_sig - sd_sig)], ...
                            pcol(p_i,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                        
                        % --- MODIFICA: Aggiunto 'DisplayName' per la legenda ---
                        plot(ax_s, x_grid, mu_sig, 'Color', pcol(p_i,:), 'LineWidth', 1.5, 'DisplayName', phase_labels{p_i});
                    end
                    title(ax_s, ch_labels{c}, 'FontWeight', 'bold', 'FontSize', 10);
                    ylim(ax_s, [0 max_y_sig * 1.1]); xlim(ax_s, [x_grid(1) x_grid(end)]);
                    if c > 3, xlabel(ax_s, 'Posizione [m]', 'FontSize', 8); end
                    if mod(c,3) == 1, ylabel(ax_s, 'Inv. RMS [m/s^2]', 'FontSize', 8); end
                    
                    % --- NUOVO: Aggiunta della legenda solo sul primo grafico (V SX-F) ---
                    if c == 1
                        legend(ax_s, 'Location', 'northwest', 'FontSize', 7);
                    end
                end
                
                sgtitle(f_temp, sprintf('Evoluzione Firma Fisica per Sensore (Dal Blu al Rosso) - %s', dir_label), 'FontWeight', 'bold', 'FontSize', 12);
                exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_3_PCA_Sig.png', rank_idx)), 'Resolution', 300);    
            catch
                % Silenzioso: se la PCA salta, le immagini non vengono prodotte e il LaTeX le ignora
            end
        end
    end
    
    % =========================================================================
    % 6. WATERFALL E PSD 3D (Stessa logica del report singolo)
    % =========================================================================
    nomi_profili = {'Verticale_SX', 'Verticale_DX', 'Laterale_DX', 'Laterale_SX'};
    titoli_profili = {'Verticale Sinistro', 'Verticale Destro', 'Laterale Destro', 'Laterale Sinistro'};
    sens_pairs = {{'left_sensor_front', 'left_sensor_rear'}, {'right_sensor_front', 'right_sensor_rear'}, ...
                  {'right_sensor_front_lat', 'right_sensor_rear_lat'}, {'left_sensor_front_lat', 'left_sensor_rear_lat'}};
                  
    nomi_psd = {'Vert_SX_Front', 'Vert_SX_Rear', 'Vert_DX_Front', 'Vert_DX_Rear', 'Lat_DX_Front', 'Lat_DX_Rear', 'Lat_SX_Front', 'Lat_SX_Rear'};
    titoli_psd = {'Vert. SX Front', 'Vert. SX Rear', 'Vert. DX Front', 'Vert. DX Rear', 'Lat. DX Front', 'Lat. DX Rear', 'Lat. SX Front', 'Lat. SX Rear'};
    
    common_axis = -C.WINDOW_SIZE : C.SPATIAL_RES : C.WINDOW_SIZE;
    
    for grp = 1:4
        s_f = sens_pairs{grp}{1}; s_r = sens_pairs{grp}{2};
        Z_mat = zeros(n_days, length(common_axis));
        
        for k = 1:n_days
            mask = find(days_floor == unique_days(k));
            sigs_mat = [];
            for j = 1:length(mask)
                run_i = History(mask(j));
                if ~isfield(run_i.Data, 'Filt') || ~isfield(run_i.Data, 'RelativeAxis'), continue; end
                ax_loc = run_i.Data.RelativeAxis;
                for s_name = {s_f, s_r}
                    if isfield(run_i.Data.Filt, s_name{1})
                        sig = double(run_i.Data.Filt.(s_name{1})); sig = sig(:);
                        if length(sig)>1 && length(ax_loc)>1
                            L = min(length(sig), length(ax_loc));
                            sig_interp = interp1(double(ax_loc(1:L)), sig(1:L), common_axis, 'linear', 0);
                            sigs_mat = [sigs_mat; sig_interp];
                        end
                    end
                end
            end
            if ~isempty(sigs_mat)
                rms_rows = zeros(size(sigs_mat));
                for row = 1:size(sigs_mat,1)
                    rms_rows(row,:) = sqrt(movmean(sigs_mat(row,:).^2, win_samples_base));
                end
                Z_mat(k,:) = mean(rms_rows, 1, 'omitnan');
            end
        end
        
        clf(f_temp); ax = axes('Parent', f_temp);
        h_wf = waterfall(ax, common_axis, unique_days, Z_mat);
        set(h_wf, 'LineWidth', 1.5, 'FaceAlpha', 0.8, 'EdgeColor', 'interp');
        view(ax, -37.5, 30); grid(ax, 'on'); colormap(ax, jet); datetick(ax, 'y', 'mmm yy', 'keeplimits');
        xlabel(ax, 'Posizione [m]'); zlabel(ax, 'RMS [m/s^2]'); title(ax, ['Waterfall ', titoli_profili{grp}]);
        exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_2_Giornaliera_A_Profilo_%s.png', rank_idx, nomi_profili{grp})), 'Resolution', 300);
    end
    
    for s = 1:8
        sn = sens_list{s};
        PSD_Mat = []; F_Ax = []; Y_Date = [];
        
        for k = 1:n_days
            mask = find(days_floor == unique_days(k));
            period_pxx = []; n_valid = 0;
            
            for j = 1:length(mask)
                run_i = History(mask(j));
                if ~isfield(run_i.Data, 'Filt') || ~isfield(run_i.Data.Filt, sn), continue; end
                sig = double(run_i.Data.Filt.(sn)); sig=sig(:); ax_loc = run_i.Data.RelativeAxis;
                if length(sig)<10 || length(ax_loc)<10, continue; end
                
                L = min(length(sig), length(ax_loc));
                sig = sig(1:L); ax_loc = ax_loc(1:L);
                m_idx = ax_loc >= -10/2 & ax_loc <= 10/2;
                sig_r = sig(m_idx);
                if length(sig_r) < 10, continue; end
                
                [pxx_r, f] = periodogram(sig_r, hamming(length(sig_r)), NFFT_val, fs_space);
                if isempty(period_pxx), period_pxx = zeros(size(pxx_r)); F_Ax = f; end
                if length(pxx_r) == length(period_pxx)
                    period_pxx = period_pxx + pxx_r; n_valid = n_valid + 1;
                end
            end
            if n_valid > 0
                PSD_Mat = [PSD_Mat; (period_pxx' / n_valid)];
                Y_Date = [Y_Date; unique_days(k)];
            end
        end
        
        clf(f_temp); ax = axes('Parent', f_temp);
        if ~isempty(PSD_Mat)
            h_wf = waterfall(ax, F_Ax, Y_Date, PSD_Mat);
            set(h_wf, 'LineWidth', 1.2, 'EdgeColor', 'interp', 'FaceAlpha', 0.7);
            view(ax, -37.5, 30); grid(ax, 'on'); colormap(ax, jet); datetick(ax, 'y', 'mmm yy', 'keeplimits');
            xlabel(ax, 'Frequenza [cicli/m]'); zlabel(ax, 'PSD');
        else
            text(ax, 0.5, 0.5, 'Nessun Dato', 'HorizontalAlignment', 'center');
        end
        title(ax, ['PSD 3D ', titoli_psd{s}]);
        exportgraphics(f_temp, fullfile(export_dir, sprintf('TOP%02d_2_Giornaliera_B_PSD_%d_%s.png', rank_idx, s, nomi_psd{s})), 'Resolution', 300);
    end
    
    close(f_temp);
end

% 
% function joints_table = load_joints_map(filename, track_type)
%     if strcmpi(track_type, 'pari')
%         sheetName = 'M2-Pari'; 
%     else
%         sheetName = 'M2-Dispari'; 
%     end
% 
%     if ~exist(filename, 'file')
%         disp(['[!] File Giunti non trovato: ' filename]);
%         joints_table = table();
%         return;
%     end
% 
%     try
%         % Rileva le opzioni e silenzia il warning sui nomi delle colonne
%         opts = detectImportOptions(filename, 'Sheet', sheetName);
%         opts.VariableNamingRule = 'preserve'; 
% 
%         % FIX: forza la colonna 2 (Position) a TESTO. In Excel alcuni valori sono
%         % numerici (interi) e altri testo (decimali): se la colonna viene tipizzata
%         % come 'double', readtable trasforma le celle-testo in NaN PRIMA della
%         % conversione, scartando i giunti decimali (es. 5792.48).
%         opts = setvartype(opts, 2, 'char');
% 
%         joints_table = readtable(filename, opts);
% 
%         % Estrae e converte la colonna Position (gestendo anche la virgola italiana)
%         pos_raw = string(joints_table{:, 2});
%         pos_num = str2double(strrep(strtrim(pos_raw), ',', '.'));
% 
%         % Riscrive la colonna nella tabella come puramente numerica
%         joints_table.(joints_table.Properties.VariableNames{2}) = pos_num;
% 
%         % Ora possiamo usare isnan in totale sicurezza per pulire le righe vuote
%         joints_table = joints_table(~isnan(pos_num), :);
% 
%         fprintf('[OK] Caricati %d giunti dal foglio %s\n', height(joints_table), sheetName);
%     catch ME
%         fprintf('[!] Errore lettura Excel Giunti: %s\n', ME.message);
%         joints_table = table();
%     end
% end



function joints_table = load_joints_map(filename, track_type)
    if strcmpi(track_type, 'pari')
        sheetName = 'M2-Pari'; 
    else
        sheetName = 'M2-Dispari'; 
    end
    
    if ~exist(filename, 'file')
        disp(['[!] File Giunti non trovato: ' filename]);
        joints_table = table();
        return;
    end
    
    try
        % readcell legge ogni cella COSI' COM'E', senza tipizzazione automatica:
        % evita che i valori decimali salvati come testo diventino NaN.
        raw = readcell(filename, 'Sheet', sheetName);
        data = raw(2:end, :);              % salta la riga di intestazione
        
        pos_raw = data(:, 2);              % Position
        nomi    = data(:, 3);              % Joint Number
        staz    = data(:, 1);              % Stations
        
        n = size(data, 1);
        pos_num = nan(n, 1);
        for i = 1:n
            v = pos_raw{i};
            if isnumeric(v) && isscalar(v)
                pos_num(i) = v;
            else
                % testo: gestisce sia il punto che la virgola decimale
                pos_num(i) = str2double(strrep(strtrim(string(v)), ',', '.'));
            end
        end
        
        % Arrotonda al metro (la precisione sub-metrica non serve)
        pos_num = round(pos_num);
        
        valid = ~isnan(pos_num);
        joints_table = table( string(staz(valid)), pos_num(valid), string(nomi(valid)), ...
            'VariableNames', {'Stations', 'Position', 'Joint'} );
        
        fprintf('[OK] Caricati %d giunti dal foglio %s\n', height(joints_table), sheetName);
    catch ME
        fprintf('[!] Errore lettura Excel Giunti: %s\n', ME.message);
        joints_table = table();
    end
end
