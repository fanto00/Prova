% =====================================================================
% export_master_db_for_python.m
% Ripulisce il formato del MASTER_DB (lo stesso prodotto dal codice
% database) per renderlo leggibile da scipy.io.loadmat in Python:
%   - Date (datetime)        -> char ISO 'yyyy-MM-dd HH:mm:ss'
%   - RunName / ID_PK / Infrastructure (string) -> char
% Non ricalcola nulla: e' solo una conversione di tipo + save -v7.
% =====================================================================

in_path  = 'C:\Users\Nicco\Desktop\Prova\Data\Database_damage_38-Garibaldi F.S. to Gioia.mat';
out_path = 'C:\Users\Nicco\Desktop\Prova\Data\Database_damage_38_py.mat';

S  = load(in_path);
DB = S.MASTER_DB;

for i = 1:numel(DB)
    if isfield(DB, 'Infrastructure')
        DB(i).Infrastructure = char(string(DB(i).Infrastructure));
    end
    if isfield(DB, 'ID_PK')
        DB(i).ID_PK = char(string(DB(i).ID_PK));
    end

    H = DB(i).History;
    for k = 1:numel(H)
        % datetime scalare -> char ISO 8601 (gestisce anche Date gia' char)
        H(k).Date = char(datetime(H(k).Date, 'Format', 'yyyy-MM-dd HH:mm:ss'));
        if isfield(H, 'RunName')
            H(k).RunName = char(string(H(k).RunName));
        end
    end
    DB(i).History = H;
end

MASTER_DB = DB;
save(out_path, 'MASTER_DB', '-v7');
fprintf('Salvato: %s\n', out_path);
