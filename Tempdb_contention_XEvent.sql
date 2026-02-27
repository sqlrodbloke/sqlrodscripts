IF EXISTS(SELECT * 
         FROM sys.server_event_sessions 
         WHERE name = 'MonitorTempdbContention')
    DROP EVENT SESSION [MonitorTempdbContention] ON SERVER;
GO
CREATE EVENT SESSION MonitorTempdbContention 
ON SERVER 
ADD EVENT sqlserver.latch_suspend_end 
(
    WHERE ( database_id=2 AND 
           duration>0 AND 
           (mode=2 OR 
               mode=3) AND 
           (page_id<4 OR -- Initial allocation bitmap pages
               package0.divides_by_uint64(page_id, 8088) OR --PFS pages
               package0.divides_by_uint64(page_id, 511232) OR  --GAM Pages
               page_id=511233 OR  --2nd SGAM page 4GB-8GB
               page_id=1022465 OR --3rd SGAM page 8GB-12GB
               page_id=1533697 OR --4th SGAM page 12GB-16GB
               page_id=2044929 OR --5th SGAM page 16GB-20GB
               page_id=2556161 OR --6th SGAM page 20GB-24GB
               page_id=3067393 OR --7th SGAM page 24GB-28GB
               page_id=3578625) --8th SGAM page 28GB-32GB
           )
       ) 
ADD TARGET package0.histogram(
   SET filtering_event_name=N'sqlserver.latch_suspend_end',
       source=N'page_id',
       source_type=0),
ADD TARGET package0.event_file(
SET filename='e:\ENDUR_PRD_DBA\Trace\Trace_MonitorTempdbContention.xel',
    max_file_size=500,
    max_rollover_files=5) 
	
	
	--Newer versions
CREATE EVENT SESSION [MonitorTempdbContention] ON SERVER 
ADD EVENT sqlserver.latch_suspend_end(
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.query_hash,sqlserver.sql_text)
    WHERE ([package0].[equal_uint64]([database_id],(2)) AND [package0].[greater_than_uint64]([duration],(5000)) AND ([package0].[equal_uint64]([mode],'SH') OR [package0].[equal_uint64]([mode],'UP')) AND ([package0].[equal_uint64]([page_type_id],'PFS_PAGE') OR [package0].[equal_uint64]([page_type_id],'GAM_PAGE') OR [package0].[equal_uint64]([page_type_id],'SGAM_PAGE'))))
ADD TARGET package0.event_file(SET filename=N'e:\ENDUR_PRD_DBA\Trace\Trace_MonitorTempdbContention.xel',max_file_size=(500),max_rollover_files=(5)),
ADD TARGET package0.histogram(SET filtering_event_name=N'sqlserver.latch_suspend_end',source=N'page_id',source_type=(0))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO



CREATE EVENT SESSION [MonitorTempdbSpills] ON SERVER 
ADD EVENT sqlserver.exchange_spill(
    ACTION(sqlserver.client_app_name,sqlserver.query_hash,sqlserver.sql_text)),
ADD EVENT sqlserver.hash_spill_details(
    ACTION(sqlserver.client_app_name,sqlserver.query_hash,sqlserver.sql_text)),
ADD EVENT sqlserver.hash_warning(
    ACTION(sqlserver.client_app_name,sqlserver.query_hash,sqlserver.sql_text)),
ADD EVENT sqlserver.sort_warning(
    ACTION(sqlserver.client_app_name,sqlserver.query_hash,sqlserver.sql_text))
ADD TARGET package0.event_file(SET filename=N'E:\ENDUR_PRD_DBA\Trace\MonitorTempdbSpills.xel',max_rollover_files=(2))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

