USE database;

DROP FUNCTION IF EXISTS sys_eval;

CREATE FUNCTION sys_eval RETURNS STRING SONAME 'libsys_eval.so';
