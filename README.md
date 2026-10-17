# Data Warehouse con Arquitectura Medallón para Minería de Datos

**Desarrollado por:** 
* Briones Sánchez Erick Alan
* Zamora Antiga Ángel Javier

---

## Contexto y Motivación en Minería de Datos

En el proceso de Descubrimiento de Conocimiento en Bases de Datos (KDD), las etapas de integración, limpieza y transformación consumen la mayor parte del esfuerzo técnico. Los sistemas operacionales en producción suelen presentar dispersión entre plataformas, redundancia de registros, formatos no tipados y anomalías transaccionales que imposibilitan el entrenamiento directo de modelos analíticos.

Este proyecto aborda dicha problemática implementando un Data Warehouse que actúa como Fuente Única de Verdad (Single Source of Truth), con tres propósitos centrales:

1. **Integración de fuentes dispersas:** Unificación de datos transaccionales y maestros originados de forma independiente en un CRM y un ERP.
2. **Homologación y calidad de datos:** Aplicación de reglas determinísticas para la deduplicación de entidades, corrección de inconsistencias contables y resolución de conflictos de atributos.
3. **Modelado para consumo analítico:** Construcción de un esquema dimensional optimizado para alimentar algoritmos de minería de datos (agrupamiento, reglas de asociación y análisis de series temporales).

---

## Arquitectura del Data Warehouse

El procesamiento de datos se fundamenta en el paradigma ELT (Extract, Load, Transform) y se organiza en tres capas progresivas:

* **Capa Bronze (Raw Data):** Zona de aterrizaje donde se realiza la ingesta directa de las fuentes transaccionales en su formato crudo, priorizando fidelidad e integridad original sin transformaciones estructurales.
* **Capa Silver (Cleansed & Conformed):** Zona de depuración donde se aplican validaciones de tipos de datos, deduplicación de identidades, estandarización de catálogos categóricos, enriquecimiento de atributos y auditoría temporal.
* **Capa Gold (Curated Star Schema):** Zona de consumo analítico modelada bajo el enfoque dimensional de Kimball, exponiendo dimensiones conformadas y una tabla de hechos granular mediante vistas SQL de alto rendimiento.

---

## Fuentes de Datos

El repositorio utiliza seis archivos en formato CSV distribuidos por sistema de origen:

| Sistema | Archivo | Entidad | Atributos Clave | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| CRM | `cust_info.csv` | Clientes | `cst_id`, `cst_key`, nombres, estado civil, género, fecha creación | Maestro de clientes registrados en la plataforma CRM. |
| CRM | `prd_info.csv` | Productos | `prd_id`, `prd_key`, nombre, costo, línea, fechas vigencia | Catálogo con historial de vigencias de productos. |
| CRM | `sales_details.csv` | Ventas | `sls_ord_num`, `sls_prd_key`, `sls_cust_id`, fechas, montos, cantidades | Detalle transaccional de órdenes de venta. |
| ERP | `CUST_AZ12.csv` | Demografía | `cid`, `bdate`, `gen` | Registro complementario de fecha de nacimiento y género. |
| ERP | `LOC_A101.csv` | Ubicación | `cid`, `cntry` | Mapeo de clientes a su respectivo país de residencia. |
| ERP | `PX_CAT_G1V2.csv` | Categorías | `id`, `cat`, `subcat`, `maintenance` | Jerarquías de producto y requerimientos de mantenimiento. |

---

## Implementación por Capas

### 1. Capa Bronze (Esquema `bronze`)

La capa Bronze aloja las tablas de ingesta directa definidas con tipos de datos permisivos para evitar rechazos durante la carga inicial.

* El procedimiento almacenado `bronze.load_bronze` automatiza la carga masiva mediante sentencias `BULK INSERT` optimizadas con bloqueo de tabla (`TABLOCK`).
* Garantiza la idempotencia mediante el vaciado previo de las tablas (`TRUNCATE TABLE`).
* Incorpora medición de tiempos de ejecución por tabla y por lote mediante `DATEDIFF`, así como control de excepciones estructurado con bloques `TRY...CATCH`.

> [!WARNING]
> **Idempotencia en Cargas Masivas**
> El procedimiento `bronze.load_bronze` ejecuta un `TRUNCATE TABLE` previo a cada `BULK INSERT`. Esto asegura la reproducibilidad de las cargas evitando duplicados acumulativos, pero implica el vaciado completo de la capa cruda antes de cada inserción.

### 2. Capa Silver (Esquema `silver`)

La capa Silver consolida los datos limpios y enriquecidos, incorporando la columna de auditoría `dwh_create_date` con valor predeterminado `GETDATE()` para asegurar el linaje de los datos.

El procedimiento almacenado `silver.load_silver` ejecuta las siguientes transformaciones de calidad:

* **Deduplicación de clientes:** Selección del registro más reciente por cliente evaluando su fecha de registro mediante la función de ventana `ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC)`.
* **Normalización categórica:** Homologación de códigos de estado civil (`S` a `Single`, `M` a `Married`), género (`F` a `Female`, `M` a `Male`) y códigos de país (`DE` a `Germany`, `US`/`USA` a `United States`).
* **Gestión de vigencias de producto:** Cálculo dinámico de la fecha de término (`prd_end_dt`) mediante la función de ventana `LEAD(prd_start_dt) OVER (...) - 1`, modelando el comportamiento de dimensiones que cambian lentamente (SCD).
* **Integridad transaccional de ventas:** Conversión de fechas almacenadas en formato numérico entero a tipo `DATE`. Recálculo automático del monto vendido cuando el registro es nulo o inconsistente (`sls_quantity * ABS(sls_price)`), y derivación del precio unitario cuando no se encuentra presente.
* **Depuración de identificadores y fechas:** Remoción de prefijos alfanuméricos y guiones en identificadores del ERP, y anulación de fechas de nacimiento incongruentes o futuras.

> [!IMPORTANT]
> **Consolidación de la Fuente Única de Verdad**
> Las transformaciones determinísticas en la capa Silver eliminan redundancias mediante deduplicación analítica con `ROW_NUMBER()` y corrigen inconsistencias numéricas y fechas anómalas, garantizando que el downstream analítico opere sobre datos fiables.

### 3. Capa Gold (Esquema `gold`)

La capa Gold expone el modelo dimensional a través de vistas SQL (`CREATE VIEW`), desacoplando el almacenamiento físico de la capa analítica y permitiendo que cualquier recarga en las capas inferiores se refleje de manera inmediata.

* Genera claves subrogadas (*Surrogate Keys*) mediante `ROW_NUMBER() OVER (...)` para desvincular el modelo de las llaves naturales de los sistemas transaccionales.
* Consolida la visión única del cliente (`gold.dim_customers`), resolviendo discrepancias de género dando prioridad al CRM con respaldo en el ERP mediante `COALESCE`, e integrando residencia y fecha de nacimiento.
* Filtra el catálogo de productos (`gold.dim_products`) para presentar únicamente los registros vigentes (`prd_end_dt IS NULL`), enriquecidos con la jerarquía de categorías y mantenimiento del ERP.
* Publica la tabla de hechos (`gold.fact_sales`) con granularidad a nivel de línea de orden, vinculada a las dimensiones mediante sus respectivas claves subrogadas y conteniendo las medidas métricas de volumen, precio y monto de venta.

> [!NOTE]
> **Arquitectura Desacoplada mediante Vistas SQL**
> El modelo dimensional en la capa Gold se implementa como vistas dinámicas en lugar de tablas físicas. Esto desacopla el almacenamiento de la presentación analítica, optimiza el espacio en disco y garantiza que cualquier actualización en las capas inferiores se propague de forma inmediata sin necesidad de pipelines adicionales.

---

## Modelo Dimensional en Estrella

El esquema dimensional resultante se estructura de la siguiente manera:

| Objeto | Tipo | Clave Primaria / Foránea | Descripción |
| :--- | :--- | :--- | :--- |
| `gold.dim_customers` | Dimensión | `customer_key` (PK) | Dimensión de clientes unificada (CRM + ERP). Incluye nombre, apellido, país, estado civil, género, fecha de nacimiento y fecha de registro. |
| `gold.dim_products` | Dimensión | `product_key` (PK) | Catálogo vigente de productos con jerarquía de categoría, subcategoría, indicador de mantenimiento, costo unitario y línea de producto. |
| `gold.fact_sales` | Tabla de Hechos | `product_key` (FK), `customer_key` (FK) | Hechos de venta a nivel de ítem por orden. Contiene número de orden, fechas (orden, envío, vencimiento), monto vendido, unidades y precio unitario. |

---

## Aplicaciones en Minería de Datos

La estructura dimensional de la capa Gold facilita la preparación de conjuntos de datos listos para algoritmos analíticos:

> [!TIP]
> **Optimización para Minería de Datos y Machine Learning**
> La estructura desnormalizada del Esquema en Estrella reduce hasta en un 80% el esfuerzo habitual de preparación de datos, permitiendo extraer de forma directa matrices de características para clustering, tablas de transacciones para reglas de asociación y series temporales agregadas.

* **Segmentación de Clientes (Clustering):** Al vincular `gold.dim_customers` con `gold.fact_sales`, es posible construir perfiles de comportamiento de compra basados en Recencia, Frecuencia y Valor Monetario (RFM), complementados con variables demográficas (edad, género, ubicación) para algoritmos como K-Means o agrupamiento jerárquico.
* **Análisis de Canasta de Compra (Reglas de Asociación):** La granularidad de `gold.fact_sales` preserva las transacciones por `order_number` asociadas a `product_key`, permitiendo generar matrices de co-ocurrencia para calcular métricas de Soporte, Confianza y Lift con algoritmos como Apriori o FP-Growth.
* **Modelado Predictivo y Series Temporales:** La estandarización de atributos temporales (`order_date`, `shipping_date`) permite formular modelos de pronóstico de demanda agregada por periodos temporales, familias de productos o territorios.

---

## Organización del Repositorio

| Ruta | Descripción |
| :--- | :--- |
| `datasets/source_crm/` | Archivos de entrada correspondientes al sistema transaccional CRM (`cust_info.csv`, `prd_info.csv`, `sales_details.csv`). |
| `datasets/source_erp/` | Archivos de entrada correspondientes al sistema ERP (`CUST_AZ12.csv`, `LOC_A101.csv`, `PX_CAT_G1V2.csv`). |
| `scripts/creacion_base.sql` | Creación de la base de datos `DataWarehouse` y los esquemas `bronze`, `silver` y `gold`. |
| `scripts/bronce/tablas_bronce.sql` | Definición de estructuras de almacenamiento crudo en la capa Bronze. |
| `scripts/bronce/carga_bronce.sql` | Procedimiento almacenado `bronze.load_bronze` para la ingesta masiva de datos. |
| `scripts/plata/tablas_plata.sql` | Definición de estructuras con campos de auditoría en la capa Silver. |
| `scripts/plata/carga_plata.sql` | Procedimiento almacenado `silver.load_silver` para deduplicación, tipado y aplicación de reglas de negocio. |
| `scripts/oro/vistas_oro.sql` | Definición de vistas analíticas `dim_customers`, `dim_products` y `fact_sales` en la capa Gold. |
| `README.md` | Documentación técnica del proyecto. |

---

## Guía de Despliegue y Ejecución

### Prerrequisitos

* Motor de base de datos Microsoft SQL Server 2017 o superior.
* Herramienta cliente para gestión de SQL Server (SQL Server Management Studio, Azure Data Studio o extensión mssql para VS Code).

### Secuencia de Ejecución

Para construir el Data Warehouse desde cero, ejecute los scripts en el siguiente orden secuencial:

1. **Inicialización de la Base de Datos:**
   Ejecutar el script `scripts/creacion_base.sql` para crear la base de datos `DataWarehouse` y los esquemas `bronze`, `silver` y `gold`.

2. **Despliegue de la Capa Bronze:**
   * Ejecutar el script `scripts/bronce/tablas_bronce.sql` para crear las tablas de almacenamiento crudo.
   * Compilar el procedimiento contenido en `scripts/bronce/carga_bronce.sql` y ejecutar la carga masiva mediante el comando `EXEC bronze.load_bronze;`.

3. **Despliegue de la Capa Plata:**
   * Ejecutar el script `scripts/plata/tablas_plata.sql` para crear las tablas estructuradas.
   * Compilar el procedimiento contenido en `scripts/plata/carga_plata.sql` y ejecutar las transformaciones mediante el comando `EXEC silver.load_silver;`.

4. **Despliegue de la Capa Oro:**
   Ejecutar el script `scripts/oro/vistas_oro.sql` para instanciar las vistas del modelo dimensional (`dim_customers`, `dim_products` y `fact_sales`).
