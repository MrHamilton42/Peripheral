local _, FW = ...
-- Neutral bootstrap only. Personal configuration lives in ForeverWorkspaceDB.
-- Configuration.lua can migrate an old generated FW.Geometry table once if
-- that legacy file is still present when the new code is first loaded.
FW.Geometry = nil
