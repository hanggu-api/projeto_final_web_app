SELECT 
    table_name, 
    column_name, 
    data_type 
FROM 
    information_schema.columns 
WHERE 
    table_schema = 'public' 
    AND table_name IN ('service_requests_new', 'providers', 'users', 'task_catalog', 'professions');
