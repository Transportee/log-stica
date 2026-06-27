-- ══════════════════════════════════════════════════════════════════
--  LOGIFAST · database.sql
--  Schema MySQL / MariaDB — Versión 1.0
--
--  Tablas:
--    1. clientes          → Personas o empresas que generan envíos
--    2. destinos          → Ciudades de destino con tarifas
--    3. cotizaciones      → Cálculos de costo generados por el frontend
--    4. envios            → Envíos confirmados a partir de una cotización
--    5. historial_estados → Auditoría de cambios de estado de cada envío
--
--  Convenciones:
--    · Charset UTF-8 MB4 (soporte emojis y caracteres especiales)
--    · InnoDB para FK y transacciones
--    · Timestamps en UTC
--    · Soft-delete en clientes (deleted_at)
-- ══════════════════════════════════════════════════════════════════

-- Crear y seleccionar la base de datos
CREATE DATABASE IF NOT EXISTS logifast
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE logifast;

-- ──────────────────────────────────────────────────────────────────
-- Desactivar checks temporalmente para una carga limpia
-- ──────────────────────────────────────────────────────────────────
SET FOREIGN_KEY_CHECKS = 0;


-- ══════════════════════════════════════════════════════════════════
-- TABLA 1: clientes
-- Personas físicas o empresas que solicitan cotizaciones o envíos.
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS clientes (
    id              INT UNSIGNED    NOT NULL AUTO_INCREMENT,

    -- Identificación
    tipo            ENUM('persona', 'empresa')  NOT NULL DEFAULT 'persona',
    nombre          VARCHAR(120)    NOT NULL,
    apellido        VARCHAR(120)    NULL,           -- NULL si es empresa
    razon_social    VARCHAR(200)    NULL,           -- NULL si es persona

    -- Contacto
    email           VARCHAR(255)    NOT NULL,
    telefono        VARCHAR(30)     NULL,
    cuit_cuil       VARCHAR(20)     NULL,           -- formato: 20-12345678-9

    -- Dirección de origen (desde donde despacha)
    direccion       VARCHAR(255)    NULL,
    ciudad_origen   VARCHAR(100)    NOT NULL DEFAULT 'Buenos Aires',
    provincia_origen VARCHAR(100)   NOT NULL DEFAULT 'Buenos Aires',

    -- Auditoría
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at      DATETIME        NULL,           -- soft-delete

    PRIMARY KEY (id),
    UNIQUE KEY uq_clientes_email (email),
    INDEX idx_clientes_nombre (nombre),
    INDEX idx_clientes_deleted (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Clientes / remitentes que usan el sistema LOGIFAST';


-- ══════════════════════════════════════════════════════════════════
-- TABLA 2: destinos
-- Ciudades de destino con sus distancias y tarifas base.
-- Permite actualizar precios sin tocar el código del frontend.
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS destinos (
    id              TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,

    ciudad          VARCHAR(100)    NOT NULL,
    provincia       VARCHAR(100)    NOT NULL,
    pais            VARCHAR(80)     NOT NULL DEFAULT 'Argentina',

    -- Logística
    distancia_km    SMALLINT UNSIGNED NOT NULL   COMMENT 'Kilómetros desde Buenos Aires',
    zona            TINYINT UNSIGNED  NOT NULL DEFAULT 1
                    COMMENT '1=corta, 2=media, 3=larga — para agrupación tarifaria',

    -- Tarifa configurable (independiente del frontend)
    costo_km        DECIMAL(8,2)    NOT NULL DEFAULT 5.00
                    COMMENT 'Costo por km en ARS',
    tarifa_base     DECIMAL(10,2)   NOT NULL DEFAULT 1000.00
                    COMMENT 'Tarifa base fija en ARS',
    costo_kg_vol    DECIMAL(8,2)    NOT NULL DEFAULT 100.00
                    COMMENT 'Costo por kg volumétrico en ARS',

    activo          TINYINT(1)      NOT NULL DEFAULT 1,

    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_destinos_ciudad (ciudad, provincia),
    INDEX idx_destinos_activo (activo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Ciudades de destino con tarifas configurables';


-- ══════════════════════════════════════════════════════════════════
-- TABLA 3: cotizaciones
-- Cada vez que el usuario presiona "Calcular Envío" en el frontend,
-- se guarda un registro aquí con todos los datos del cálculo.
-- Una cotización puede o no convertirse en un envío real.
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS cotizaciones (
    id              INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    codigo          VARCHAR(15)     NOT NULL
                    COMMENT 'ID legible por el usuario, ej: LGF-ABC1234',

    -- Relaciones (cliente es opcional: cotización puede ser anónima)
    cliente_id      INT UNSIGNED    NULL,
    destino_id      TINYINT UNSIGNED NOT NULL,

    -- Dimensiones del paquete al momento de cotizar
    alto_cm         DECIMAL(7,2)    NOT NULL,
    ancho_cm        DECIMAL(7,2)    NOT NULL,
    largo_cm        DECIMAL(7,2)    NOT NULL,

    -- Resultados del cálculo (se guardan fijos para auditoría)
    peso_volumetrico_kg  DECIMAL(10,4) NOT NULL
                    COMMENT '(alto × ancho × largo) / 5000',
    volumen_cm3     DECIMAL(14,2)   NOT NULL
                    COMMENT 'alto × ancho × largo',

    tarifa_base_ars      DECIMAL(10,2) NOT NULL,
    recargo_distancia_ars DECIMAL(10,2) NOT NULL,
    costo_vol_ars        DECIMAL(10,2) NOT NULL,
    total_ars            DECIMAL(12,2) NOT NULL,

    -- Snapshot de las tarifas usadas (por si cambian en el futuro)
    snapshot_costo_km    DECIMAL(8,2)  NOT NULL,
    snapshot_costo_kg_vol DECIMAL(8,2) NOT NULL,

    -- Estado de la cotización
    estado          ENUM('pendiente', 'convertida', 'vencida', 'cancelada')
                    NOT NULL DEFAULT 'pendiente',

    -- Metadatos de sesión (útil sin login)
    ip_origen       VARCHAR(45)     NULL    COMMENT 'IPv4 o IPv6',
    user_agent      VARCHAR(300)    NULL,

    -- Auditoría
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    vence_at        DATETIME        NOT NULL
                    DEFAULT (CURRENT_TIMESTAMP + INTERVAL 48 HOUR)
                    COMMENT 'Las cotizaciones vencen 48 h después de crearse',

    PRIMARY KEY (id),
    UNIQUE KEY uq_cotizaciones_codigo (codigo),
    INDEX idx_cot_cliente (cliente_id),
    INDEX idx_cot_destino (destino_id),
    INDEX idx_cot_estado (estado),
    INDEX idx_cot_created (created_at),

    CONSTRAINT fk_cot_cliente
        FOREIGN KEY (cliente_id) REFERENCES clientes (id)
        ON DELETE SET NULL ON UPDATE CASCADE,

    CONSTRAINT fk_cot_destino
        FOREIGN KEY (destino_id) REFERENCES destinos (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Cotizaciones generadas por el calculador del frontend';


-- ══════════════════════════════════════════════════════════════════
-- TABLA 4: envios
-- Un envío es una cotización confirmada y pagada.
-- Hereda los datos de la cotización y agrega info operativa.
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS envios (
    id              INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    numero_seguimiento VARCHAR(20)  NOT NULL
                    COMMENT 'Código público de tracking, ej: LGF-ENV-00001',

    -- Relaciones
    cotizacion_id   INT UNSIGNED    NOT NULL,
    cliente_id      INT UNSIGNED    NOT NULL,
    destino_id      TINYINT UNSIGNED NOT NULL,

    -- Datos del destinatario
    destinatario_nombre   VARCHAR(200) NOT NULL,
    destinatario_telefono VARCHAR(30)  NULL,
    destinatario_email    VARCHAR(255) NULL,
    direccion_entrega     VARCHAR(300) NOT NULL,
    ciudad_entrega        VARCHAR(100) NOT NULL,
    codigo_postal         VARCHAR(10)  NULL,

    -- Estado operativo del envío
    estado          ENUM(
                        'confirmado',       -- pago recibido
                        'en_preparacion',   -- armando el paquete
                        'en_transito',      -- salió del depósito
                        'en_distribucion',  -- última milla
                        'entregado',        -- entrega exitosa
                        'devuelto',         -- no se pudo entregar
                        'cancelado'
                    ) NOT NULL DEFAULT 'confirmado',

    -- Costo final (puede diferir levemente de la cotización)
    costo_final_ars DECIMAL(12,2)   NOT NULL,

    -- Fechas clave
    fecha_confirmacion  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_despacho      DATETIME    NULL,
    fecha_entrega_est   DATE        NULL    COMMENT 'Fecha estimada de entrega',
    fecha_entrega_real  DATETIME    NULL    COMMENT 'Fecha real de entrega',

    -- Observaciones internas
    notas_internas  TEXT            NULL,

    -- Auditoría
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_envios_numero (numero_seguimiento),
    UNIQUE KEY uq_envios_cotizacion (cotizacion_id),
    INDEX idx_env_cliente (cliente_id),
    INDEX idx_env_destino (destino_id),
    INDEX idx_env_estado (estado),
    INDEX idx_env_created (created_at),

    CONSTRAINT fk_env_cotizacion
        FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT fk_env_cliente
        FOREIGN KEY (cliente_id) REFERENCES clientes (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT fk_env_destino
        FOREIGN KEY (destino_id) REFERENCES destinos (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Envíos confirmados derivados de cotizaciones';


-- ══════════════════════════════════════════════════════════════════
-- TABLA 5: historial_estados
-- Auditoría inmutable de cada cambio de estado de un envío.
-- Permite reconstruir el timeline completo de un paquete.
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS historial_estados (
    id              INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    envio_id        INT UNSIGNED    NOT NULL,

    estado_anterior VARCHAR(30)     NULL    COMMENT 'NULL en la transición inicial',
    estado_nuevo    VARCHAR(30)     NOT NULL,

    -- Contexto del cambio
    ubicacion       VARCHAR(200)    NULL    COMMENT 'Depósito, ciudad, etc.',
    descripcion     VARCHAR(400)    NULL    COMMENT 'Mensaje público de tracking',
    operador        VARCHAR(120)    NULL    COMMENT 'Usuario del sistema que hizo el cambio',

    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX idx_hist_envio (envio_id),
    INDEX idx_hist_created (created_at),

    CONSTRAINT fk_hist_envio
        FOREIGN KEY (envio_id) REFERENCES envios (id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Historial inmutable de estados de cada envío (tracking)';


-- ──────────────────────────────────────────────────────────────────
-- Re-activar checks
-- ──────────────────────────────────────────────────────────────────
SET FOREIGN_KEY_CHECKS = 1;


-- ══════════════════════════════════════════════════════════════════
-- DATOS INICIALES (SEED)
-- ══════════════════════════════════════════════════════════════════

-- Destinos del frontend (con las mismas tarifas del calculador)
INSERT INTO destinos (ciudad, provincia, distancia_km, zona, costo_km, tarifa_base, costo_kg_vol) VALUES
    ('Rosario',         'Santa Fe',  300,  1, 5.00, 1000.00, 100.00),
    ('Córdoba Capital', 'Córdoba',   700,  2, 5.00, 1000.00, 100.00),
    ('Mendoza',         'Mendoza',   1050, 2, 5.00, 1000.00, 100.00),
    ('Tucumán',         'Tucumán',   1200, 3, 5.00, 1000.00, 100.00),
    ('Salta',           'Salta',     1450, 3, 5.00, 1000.00, 100.00);

-- Cliente de prueba
INSERT INTO clientes (tipo, nombre, apellido, email, telefono, ciudad_origen) VALUES
    ('persona',  'Juan',    'Pérez',    'juan.perez@email.com',    '+54 9 11 1234-5678', 'Buenos Aires'),
    ('empresa',  'LogiTest S.A.', NULL, 'contacto@logitest.com.ar', '+54 9 11 9876-5432', 'Buenos Aires');

-- Cotización de ejemplo (cliente 1 → Córdoba)
INSERT INTO cotizaciones (
    codigo, cliente_id, destino_id,
    alto_cm, ancho_cm, largo_cm,
    peso_volumetrico_kg, volumen_cm3,
    tarifa_base_ars, recargo_distancia_ars, costo_vol_ars, total_ars,
    snapshot_costo_km, snapshot_costo_kg_vol,
    estado
) VALUES (
    'LGF-ABC1001', 1, 2,
    30, 40, 50,
    12.00, 60000.00,
    1000.00, 3500.00, 1200.00, 5700.00,
    5.00, 100.00,
    'convertida'
);

-- Envío derivado de esa cotización
INSERT INTO envios (
    numero_seguimiento, cotizacion_id, cliente_id, destino_id,
    destinatario_nombre, destinatario_telefono, destinatario_email,
    direccion_entrega, ciudad_entrega, codigo_postal,
    estado, costo_final_ars, fecha_entrega_est
) VALUES (
    'LGF-ENV-00001', 1, 1, 2,
    'María García', '+54 9 351 555-0001', 'maria@email.com',
    'Av. Colón 1234, Piso 3 B', 'Córdoba Capital', '5000',
    'en_transito', 5700.00, DATE_ADD(CURDATE(), INTERVAL 3 DAY)
);

-- Historial de estados de ese envío
INSERT INTO historial_estados (envio_id, estado_anterior, estado_nuevo, ubicacion, descripcion, operador) VALUES
    (1, NULL,           'confirmado',     'Centro logístico CABA',   'Pago confirmado. Envío registrado.',              'sistema'),
    (1, 'confirmado',   'en_preparacion', 'Depósito Villa del Parque','El paquete está siendo preparado para despacho.', 'operador01'),
    (1, 'en_preparacion','en_transito',   'Ruta Nacional 9',          'El paquete salió hacia Córdoba Capital.',         'operador01');


-- ══════════════════════════════════════════════════════════════════
-- VISTAS ÚTILES
-- ══════════════════════════════════════════════════════════════════

-- Vista: cotizaciones con nombre de cliente y destino
CREATE OR REPLACE VIEW v_cotizaciones AS
SELECT
    c.id,
    c.codigo,
    c.estado,
    COALESCE(cl.nombre, 'Anónimo')      AS cliente,
    cl.email                             AS cliente_email,
    d.ciudad                             AS destino,
    d.distancia_km,
    c.alto_cm, c.ancho_cm, c.largo_cm,
    c.peso_volumetrico_kg,
    c.tarifa_base_ars,
    c.recargo_distancia_ars,
    c.costo_vol_ars,
    c.total_ars,
    c.created_at,
    c.vence_at
FROM  cotizaciones c
LEFT  JOIN clientes cl ON cl.id = c.cliente_id
JOIN  destinos d       ON d.id  = c.destino_id;

-- Vista: envíos con su último estado y datos completos
CREATE OR REPLACE VIEW v_envios AS
SELECT
    e.id,
    e.numero_seguimiento,
    e.estado,
    CONCAT(cl.nombre, ' ', COALESCE(cl.apellido, '')) AS remitente,
    cl.email                                            AS remitente_email,
    d.ciudad                                            AS destino,
    e.destinatario_nombre,
    e.direccion_entrega,
    e.costo_final_ars,
    e.fecha_confirmacion,
    e.fecha_despacho,
    e.fecha_entrega_est,
    e.fecha_entrega_real,
    cot.codigo                                          AS codigo_cotizacion
FROM  envios e
JOIN  clientes    cl  ON cl.id  = e.cliente_id
JOIN  destinos    d   ON d.id   = e.destino_id
JOIN  cotizaciones cot ON cot.id = e.cotizacion_id;

-- Vista: timeline de tracking de un envío
CREATE OR REPLACE VIEW v_tracking AS
SELECT
    e.numero_seguimiento,
    e.destinatario_nombre,
    d.ciudad AS destino,
    h.estado_nuevo   AS estado,
    h.ubicacion,
    h.descripcion,
    h.operador,
    h.created_at     AS fecha_evento
FROM  historial_estados h
JOIN  envios e ON e.id = h.envio_id
JOIN  destinos d ON d.id = e.destino_id
ORDER BY h.envio_id, h.created_at;


-- ══════════════════════════════════════════════════════════════════
-- STORED PROCEDURE: registrar cambio de estado de un envío
-- Uso: CALL sp_cambiar_estado(1, 'en_distribucion', 'Córdoba', 'Llegó al centro de distribución', 'operador02');
-- ══════════════════════════════════════════════════════════════════
DELIMITER $$

CREATE PROCEDURE IF NOT EXISTS sp_cambiar_estado (
    IN  p_envio_id      INT UNSIGNED,
    IN  p_estado_nuevo  VARCHAR(30),
    IN  p_ubicacion     VARCHAR(200),
    IN  p_descripcion   VARCHAR(400),
    IN  p_operador      VARCHAR(120)
)
BEGIN
    DECLARE v_estado_actual VARCHAR(30);

    -- Obtener estado actual
    SELECT estado INTO v_estado_actual
    FROM envios WHERE id = p_envio_id FOR UPDATE;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Envío no encontrado';
    END IF;

    -- Actualizar estado en envios
    UPDATE envios
    SET    estado     = p_estado_nuevo,
           updated_at = CURRENT_TIMESTAMP,
           fecha_despacho     = IF(p_estado_nuevo = 'en_transito'  AND fecha_despacho IS NULL,     CURRENT_TIMESTAMP, fecha_despacho),
           fecha_entrega_real = IF(p_estado_nuevo = 'entregado'    AND fecha_entrega_real IS NULL,  CURRENT_TIMESTAMP, fecha_entrega_real)
    WHERE  id = p_envio_id;

    -- Insertar en historial
    INSERT INTO historial_estados
        (envio_id, estado_anterior, estado_nuevo, ubicacion, descripcion, operador)
    VALUES
        (p_envio_id, v_estado_actual, p_estado_nuevo, p_ubicacion, p_descripcion, p_operador);

    SELECT CONCAT('Estado actualizado: ', v_estado_actual, ' → ', p_estado_nuevo) AS resultado;
END$$

DELIMITER ;


-- ══════════════════════════════════════════════════════════════════
-- ÍNDICES ADICIONALES DE PERFORMANCE
-- ══════════════════════════════════════════════════════════════════

-- Búsqueda de cotizaciones recientes por cliente
CREATE INDEX idx_cot_cliente_created ON cotizaciones (cliente_id, created_at DESC);

-- Búsqueda de envíos activos (no entregados, no cancelados)
CREATE INDEX idx_env_estado_fecha ON envios (estado, fecha_confirmacion DESC);

-- Tracking por número de seguimiento (búsqueda pública)
CREATE INDEX idx_env_tracking ON envios (numero_seguimiento, estado);
