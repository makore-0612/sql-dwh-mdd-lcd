-- Procedimiento para carga de datos desde los CSV

CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        SET @start_time = GETDATE(); -- Metadatos de la carga
        TRUNCATE TABLE bronze.crm_cust_info; -- Eliminamos la información actual si es que la tiene
        BULK INSERT bronze.crm_cust_info -- Usamos BULK INSERT para copiar del CSV
        FROM '"C:\Users\AJZA0\Desktop\Licenciatura\sql-dwh-mdd-lcd\datasets\source_crm\cust_info.csv"'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @start_time = GETDATE();
        TRUNCATE TABLE bronze.crm_prd_info; -- Proceso análogo para el resto de tablas
        BULK INSERT bronze.crm_prd_info
        FROM '"C:\Users\AJZA0\Desktop\Licenciatura\sql-dwh-mdd-lcd\datasets\source_crm\prd_info.csv"'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @start_time = GETDATE();
        TRUNCATE TABLE bronze.crm_sales_details;    
        BULK INSERT bronze.crm_sales_details
        FROM '"C:\Users\AJZA0\Desktop\Licenciatura\sql-dwh-mdd-lcd\datasets\source_crm\sales_details.csv"'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @start_time = GETDATE();
        TRUNCATE TABLE bronze.erp_loc_a101;
        BULK INSERT bronze.erp_loc_a101
        FROM '"C:\Users\AJZA0\Desktop\Licenciatura\sql-dwh-mdd-lcd\datasets\source_erp\LOC_A101.csv"'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @start_time = GETDATE();
        TRUNCATE TABLE bronze.erp_cust_az12;
        BULK INSERT bronze.erp_cust_az12
        FROM '"C:\Users\AJZA0\Desktop\Licenciatura\sql-dwh-mdd-lcd\datasets\source_erp\CUST_AZ12.csv"'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @start_time = GETDATE();
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;
        BULK INSERT bronze.erp_px_cat_g1v2
        FROM '"C:\Users\AJZA0\Desktop\Licenciatura\sql-dwh-mdd-lcd\datasets\source_erp\CUST_AZ12.csv"'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';

        SET @batch_end_time = GETDATE();
        PRINT '=========================================='
        PRINT 'Loading Bronze Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '=========================================='
    END TRY
    BEGIN CATCH -- Manejo de errores
        PRINT '=========================================='
        PRINT 'ERROR OCCURRED DURING LOADING BRONZE LAYER'
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: ' + CAST (ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State: ' + CAST (ERROR_STATE() AS NVARCHAR);
        PRINT '=========================================='
    END CATCH
END
