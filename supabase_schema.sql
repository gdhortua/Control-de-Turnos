-- ====================================================================
-- CONTROL DE TURNOS Y CONCILIACIÓN BIOMÉTRICA (PDV)
-- ESQUEMA DE BASE DE DATOS Y DATOS MAESTROS PARA SUPABASE (POSTGRESQL)
-- ====================================================================

-- 1. Habilitar extensión para UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Eliminar tablas previas si existen (limpieza controlada)
DROP TABLE IF EXISTS supplementary_justifications CASCADE;
DROP TABLE IF EXISTS punch_records CASCADE;
DROP TABLE IF EXISTS punch_batches CASCADE;
DROP TABLE IF EXISTS permissions CASCADE;
DROP TABLE IF EXISTS schedules CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS pdvs CASCADE;
DROP TABLE IF EXISTS supervisors CASCADE;
DROP TABLE IF EXISTS app_config CASCADE;

-- ====================================================================
-- 3. CREACIÓN DE TABLAS
-- ====================================================================

-- Tabla: app_config (Reglas de negocio y parámetros CST)
CREATE TABLE app_config (
    id TEXT PRIMARY KEY DEFAULT 'default',
    lunch_duration_hours NUMERIC(4,2) DEFAULT 1.5,
    lunch_cutoff_time TEXT DEFAULT '12:30',
    lunch_min_shift_duration NUMERIC(4,2) DEFAULT 6.0,
    day_start_time TEXT DEFAULT '06:00',
    night_start_time TEXT DEFAULT '21:00',
    weekly_max_standard_hours INTEGER DEFAULT 42,
    max_sundays_per_month INTEGER DEFAULT 2,
    late_tolerance_minutes INTEGER DEFAULT 10,
    early_exit_tolerance_minutes INTEGER DEFAULT 10,
    maintenance_approval_email TEXT DEFAULT 'mantenimiento.obras@quest.com.co',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla: supervisors (Zonas y Supervisores Regionales)
CREATE TABLE supervisors (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    zone_code TEXT,
    zone_name TEXT,
    document_id TEXT,
    phone TEXT,
    email TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla: pdvs (Maestro de Puntos de Venta)
CREATE TABLE pdvs (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    city TEXT,
    zone_id TEXT,
    zone_name TEXT,
    supervisor_id TEXT REFERENCES supervisors(id) ON DELETE SET NULL,
    opening_hour TEXT DEFAULT '10:00',
    closing_hour TEXT DEFAULT '20:30',
    allowed_shifts JSONB DEFAULT '["10:00-20:30", "10:00-18:00", "11:00-19:00", "12:00-20:30", "13:00-20:30"]'::jsonb,
    habitual_schedule JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla: users (Usuarios del Sistema, Colaboradores y Perfiles)
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE,
    password TEXT,
    document_id TEXT,
    code TEXT,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL,
    position TEXT,
    area TEXT,
    contract_type TEXT DEFAULT 'FIJO',
    pdv_id TEXT REFERENCES pdvs(id) ON DELETE SET NULL,
    supervisor_id TEXT REFERENCES supervisors(id) ON DELETE SET NULL,
    weekly_max_hours INTEGER DEFAULT 42,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla: schedules (Programaciones Semanales de Horarios)
CREATE TABLE schedules (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    pdv_id TEXT REFERENCES pdvs(id) ON DELETE CASCADE,
    week_start TEXT NOT NULL,
    week_end TEXT NOT NULL,
    is_submitted BOOLEAN DEFAULT TRUE,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    shifts JSONB NOT NULL DEFAULT '[]'::jsonb,
    total_net_hours NUMERIC(6,2) DEFAULT 0,
    total_lunch_hours NUMERIC(6,2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_week UNIQUE (user_id, week_start)
);

-- Tabla: permissions (Permisos, Novedades y Justificaciones)
CREATE TABLE permissions (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    employee_name TEXT NOT NULL,
    document_id TEXT,
    position TEXT,
    pdv_id TEXT REFERENCES pdvs(id) ON DELETE SET NULL,
    supervisor_id TEXT REFERENCES supervisors(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    shift_type TEXT NOT NULL,
    is_day_off_change BOOLEAN DEFAULT FALSE,
    requested_start_time TEXT,
    requested_end_time TEXT,
    reason TEXT NOT NULL,
    assigned_area TEXT DEFAULT 'Líder de Zona',
    recipient_role TEXT DEFAULT 'SUPERVISOR',
    notification_email TEXT,
    email_sent BOOLEAN DEFAULT FALSE,
    email_sent_at TIMESTAMPTZ,
    status TEXT DEFAULT 'PENDING',
    supervisor_notes TEXT,
    reviewer_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

-- Tabla: punch_batches (Lotes de Carga Biométricos)
CREATE TABLE punch_batches (
    id TEXT PRIMARY KEY,
    file_name TEXT,
    file_size NUMERIC,
    period TEXT,
    store TEXT,
    uploaded_at TIMESTAMPTZ DEFAULT NOW(),
    record_count INTEGER DEFAULT 0
);

-- Tabla: punch_records (Registros Biométricos / Marcaciones Reales)
CREATE TABLE punch_records (
    id TEXT PRIMARY KEY,
    batch_id TEXT REFERENCES punch_batches(id) ON DELETE CASCADE,
    document_id TEXT,
    code TEXT,
    full_name TEXT,
    position TEXT,
    pdv_name TEXT,
    supervisor_name TEXT,
    entry_date TEXT,
    entry_time TEXT,
    exit_date TEXT,
    exit_time TEXT,
    real_calculations JSONB DEFAULT '{}'::jsonb,
    raw_row JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla: supplementary_justifications (Justificaciones de Tiempos Suplementarios)
CREATE TABLE supplementary_justifications (
    id TEXT PRIMARY KEY,
    pdv_id TEXT REFERENCES pdvs(id) ON DELETE CASCADE,
    pdv_name TEXT,
    supervisor_id TEXT REFERENCES supervisors(id) ON DELETE SET NULL,
    week_start TEXT NOT NULL,
    reason TEXT NOT NULL,
    hours_increase NUMERIC(6,2) DEFAULT 0,
    submitted_by TEXT,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'SUBMITTED'
);

-- ====================================================================
-- 4. ÍNDICES DE RENDIMIENTO
-- ====================================================================
CREATE INDEX IF NOT EXISTS idx_schedules_week ON schedules (week_start);
CREATE INDEX IF NOT EXISTS idx_schedules_pdv ON schedules (pdv_id);
CREATE INDEX IF NOT EXISTS idx_permissions_status ON permissions (status);
CREATE INDEX IF NOT EXISTS idx_permissions_user ON permissions (user_id);
CREATE INDEX IF NOT EXISTS idx_punch_records_doc ON punch_records (document_id);
CREATE INDEX IF NOT EXISTS idx_punch_records_date ON punch_records (entry_date);

-- ====================================================================
-- 5. POLÍTICAS DE ACCESO (ROW LEVEL SECURITY - RLS)
-- Permite acceso completo para la API del Frontend (Vercel / Anon Key)
-- ====================================================================
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE supervisors ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdvs ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE punch_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE punch_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplementary_justifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public Access app_config" ON app_config FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access supervisors" ON supervisors FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access pdvs" ON pdvs FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access users" ON users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access schedules" ON schedules FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access permissions" ON permissions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access punch_batches" ON punch_batches FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access punch_records" ON punch_records FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public Access supplementary_justifications" ON supplementary_justifications FOR ALL USING (true) WITH CHECK (true);

-- ====================================================================
-- 6. CARGA DE DATOS MAESTROS (SEED DATA)
-- ====================================================================

-- 6.1 Configuración CST
INSERT INTO app_config (id, lunch_duration_hours, lunch_cutoff_time, lunch_min_shift_duration, day_start_time, night_start_time, weekly_max_standard_hours, max_sundays_per_month, late_tolerance_minutes, early_exit_tolerance_minutes, maintenance_approval_email)
VALUES ('default', 1.5, '12:30', 6.0, '06:00', '21:00', 42, 2, 10, 10, 'mantenimiento.obras@quest.com.co')
ON CONFLICT (id) DO UPDATE SET 
  weekly_max_standard_hours = EXCLUDED.weekly_max_standard_hours,
  maintenance_approval_email = EXCLUDED.maintenance_approval_email;

-- 6.2 Zonas y Supervisores
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-1', 'LÍDER ZONA 2', 'COD-ZONE-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', '1018456780', 'lider.zone-1@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-2', 'LÍDER CALI 1', 'COD-ZONE-2', 'ZONA CALI 1', '1018456781', 'lider.zone-2@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-3', 'LÍDER VALLE CENTRO', 'COD-ZONE-3', 'ZONA VALLE CENTRO', '1018456782', 'lider.zone-3@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-4', 'LÍDER CALI 2 Y CAUCA', 'COD-ZONE-4', 'ZONA CALI 2 Y CAUCA', '1018456783', 'lider.zone-4@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-5', 'LÍDER COSTA NORTE', 'COD-ZONE-5', 'ZONA COSTA NORTE', '1018456784', 'lider.zone-5@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-6', 'LÍDER SANTANDERES', 'COD-ZONE-6', 'ZONA SANTANDERES', '1018456785', 'lider.zone-6@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-7', 'LÍDER VALLE SUR Y CAUCA', 'COD-ZONE-7', 'ZONA VALLE SUR Y CAUCA', '1018456786', 'lider.zone-7@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-8', 'LÍDER EJE CAFETERO 1', 'COD-ZONE-8', 'ZONA EJE CAFETERO 1', '1018456787', 'lider.zone-8@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-9', 'LÍDER NARIÑO', 'COD-ZONE-9', 'ZONA NARIÑO', '1018456788', 'lider.zone-9@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-10', 'LÍDER TOLHUCA', 'COD-ZONE-10', 'ZONA TOLHUCA', '1018456789', 'lider.zone-10@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-11', 'LÍDER COSTA SUR', 'COD-ZONE-11', 'ZONA COSTA SUR', '1018456790', 'lider.zone-11@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-12', 'LÍDER EJE CAFETERO 2', 'COD-ZONE-12', 'ZONA EJE CAFETERO 2', '1018456791', 'lider.zone-12@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-13', 'LÍDER ZONA 1', 'COD-ZONE-13', 'ZONA CENTRO (LIDER 1)', '1018456792', 'lider.zone-13@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-14', 'LÍDER ZONA 1', 'COD-ZONE-14', 'ZONA ANTIOQUIA (LIDER 1)', '1018456793', 'lider.zone-14@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;
INSERT INTO supervisors (id, name, zone_code, zone_name, document_id, email)
VALUES ('zone-15', 'LÍDER ZONA 2', 'COD-ZONE-15', 'ZONA CENTRO (LIDER 2)', '1018456794', 'lider.zone-15@empresa.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, zone_name = EXCLUDED.zone_name;

-- 6.3 Maestro de 101 Puntos de Venta (PDVs)
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-1', 'N10', 'N10 - MEDELLÍN - C.C. DEMODA OUTLET', 'MEDELLÍN', 'zone-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', 'zone-1', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-2', 'Q003', 'Q003 - Cali - Calle 23', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-3', 'Q007', 'Q007 - Tulua - Centro', 'Tulua', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-4', 'Q008', 'Q008 - Cali - Alameda', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-5', 'Q014', 'Q014 - Tulua - Cc Herradura', 'Tulua', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-6', 'Q016', 'Q016 - Cali - Cc Palmetto', 'Cali', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-7', 'Q018', 'Q018 - Cali - Cc Jardin Plaza', 'Cali', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-8', 'Q021', 'Q021 - Cali - Cc Chipichape', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-9', 'Q023', 'Q023 - Barranquilla - Cc Portal', 'Barranquilla', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-10', 'Q027', 'Q027 - Cucuta - Cc Ventura Plaza', 'Cucuta', 'zone-6', 'ZONA SANTANDERES', 'zone-6', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-11', 'Q028', 'Q028 - Cali - Centro Calle 13', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-12', 'Q029', 'Q029 - Cali - Cc Unico 1', 'Cali', 'zone-7', 'ZONA VALLE SUR Y CAUCA', 'zone-7', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-13', 'Q030', 'Q030 - Popayan - Cc Campanario', 'Popayan', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-14', 'Q031', 'Q031 - Cali - Centro 1', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-15', 'Q033', 'Q033 - Cartagena - Cc Caribe Plaza', 'Cartagena', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-16', 'Q035', 'Q035 - Barranquilla - Cc Unico', 'Barranquilla', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-17', 'Q038', 'Q038 - Pereira - Cc Unicentro', 'Pereira', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-18', 'Q039', 'Q039 - CALI - CC UNICO 2', 'CALI', 'zone-7', 'ZONA VALLE SUR Y CAUCA', 'zone-7', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-19', 'Q040', 'Q040 - Cali - Cc Unicentro 2', 'Cali', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-20', 'Q041', 'Q041 - Cali - Cc Calima', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-21', 'Q044', 'Q044 - Popayan - Centro', 'Popayan', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-22', 'Q045', 'Q045 - Pasto - Cc Unicentro', 'Pasto', 'zone-9', 'ZONA NARIÑO', 'zone-9', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-23', 'Q046', 'Q046 - Cucuta - Centro 2', 'Cucuta', 'zone-6', 'ZONA SANTANDERES', 'zone-6', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-24', 'Q049', 'Q049 - Dosquebradas - Cc Unico', 'Dosquebradas', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-25', 'Q053', 'Q053 - Neiva - Cc San Pedro Plaza', 'Neiva', 'zone-10', 'ZONA TOLHUCA', 'zone-10', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-26', 'Q054', 'Q054 - Sincelejo - Centro', 'Sincelejo', 'zone-11', 'ZONA COSTA SUR', 'zone-11', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-27', 'Q056', 'Q056 - Pitalito - Cc San Antonio', 'Pitalito', 'zone-10', 'ZONA TOLHUCA', 'zone-10', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-28', 'Q057', 'Q057 - Pasto - Cc Unico', 'Pasto', 'zone-9', 'ZONA NARIÑO', 'zone-9', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-29', 'Q058', 'Q058 - Pereira - Cc Victoria Plaza', 'Pereira', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-30', 'Q061', 'Q061 - Armenia - Cc Unicentro', 'Armenia', 'zone-12', 'ZONA EJE CAFETERO 2', 'zone-12', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-31', 'Q062', 'Q062 - Monteria - Cc Alamedas', 'Monteria', 'zone-11', 'ZONA COSTA SUR', 'zone-11', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-32', 'Q068', 'Q068 - Cartagena - Cc Outlet del Bosque', 'Cartagena', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-33', 'Q069', 'Q069 - Ibague - Centro', 'Ibague', 'zone-12', 'ZONA EJE CAFETERO 2', 'zone-12', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-34', 'Q071', 'Q071 - Neiva - Centro', 'Neiva', 'zone-10', 'ZONA TOLHUCA', 'zone-10', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-35', 'Q073', 'Q073 - Yumbo - Cc Unico', 'Yumbo', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-36', 'Q074', 'Q074 - Villavicencio - Cc Unico', 'Villavicencio', 'zone-13', 'ZONA CENTRO (LIDER 1)', 'zone-13', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-37', 'Q076', 'Q076 - Medellin - Cc Florida', 'Medellin', 'zone-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', 'zone-1', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-38', 'Q077', 'Q077 - Florencia - Cc Gran Plaza', 'Florencia', 'zone-10', 'ZONA TOLHUCA', 'zone-10', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-39', 'Q078', 'Q078 - Soledad - Cc Gran Plaza', 'Soledad', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-40', 'Q080', 'Q080 - Valledupar - Cc Mayales', 'Valledupar', 'zone-13', 'ZONA CENTRO (LIDER 1)', 'zone-13', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-41', 'Q083', 'Q083 - Yopal - Cc Unicentro', 'Yopal', 'zone-13', 'ZONA CENTRO (LIDER 1)', 'zone-13', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-42', 'Q084', 'Q084 - Santa Marta - Centro', 'Santa Marta', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-43', 'Q085', 'Q085 - Ibague - Cc La Estacion', 'Ibague', 'zone-12', 'ZONA EJE CAFETERO 2', 'zone-12', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-44', 'Q086', 'Q086 - Villavicencio - Cc Viva', 'Villavicencio', 'zone-13', 'ZONA CENTRO (LIDER 1)', 'zone-13', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-45', 'Q087', 'Q087 - Palmira - Centro', 'Palmira', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-46', 'Q088', 'Q088 - Palmira - Cc Llanogrande', 'Palmira', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-47', 'Q089', 'Q089 - Palmira - Cc Unicentro', 'Palmira', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-48', 'Q090', 'Q090 - Ipiales - Cc Gran Plaza', 'Ipiales', 'zone-9', 'ZONA NARIÑO', 'zone-9', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-49', 'Q091', 'Q091 - Armenia - Centro', 'Armenia', 'zone-12', 'ZONA EJE CAFETERO 2', 'zone-12', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-50', 'Q092', 'Q092 - Cartagena - Cc San Fernando', 'Cartagena', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-51', 'Q094', 'Q094 - Medellin - Cc Aventura', 'Medellin', 'zone-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', 'zone-1', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-52', 'Q097', 'Q097 - Cartago - Centro', 'Cartago', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-53', 'Q102', 'Q102 - Valledupar - Cc Guatapuri', 'Valledupar', 'zone-13', 'ZONA CENTRO (LIDER 1)', 'zone-13', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-54', 'Q105', 'Q105 - Pereira - Centro', 'Pereira', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-55', 'Q106', 'Q106 - Soledad - Cc Nuestro Atlantico', 'Soledad', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-56', 'Q107', 'Q107 - Monteria - Cc Nuestro Monteria', 'Monteria', 'zone-11', 'ZONA COSTA SUR', 'zone-11', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-57', 'Q109', 'Q109 - Cartagena - Cc La Castellana', 'Cartagena', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-58', 'Q112', 'Q112 - Medellin - Cc Molinos Medellin', 'Medellin', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-59', 'Q113', 'Q113 - Envigado - Cc Viva Local-221', 'Envigado', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-60', 'Q115', 'Q115 - Cucuta - Centro', 'Cucuta', 'zone-6', 'ZONA SANTANDERES', 'zone-6', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-61', 'Q116', 'Q116 - Cartago - Cc Nuestro Cartago', 'Cartago', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-62', 'Q117', 'Q117 - Neiva - Cc Unico', 'Neiva', 'zone-10', 'ZONA TOLHUCA', 'zone-10', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-63', 'Q118', 'Q118 - Sincelejo - Cc Guacari', 'Sincelejo', 'zone-11', 'ZONA COSTA SUR', 'zone-11', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-64', 'Q120', 'Q120 - Cali- Plaza Q', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-65', 'Q122', 'Q122 - Tulua- Centro Calle 27', 'Tulua', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-66', 'Q124', 'Q124 - Bogotá - Cc Nuestro Bogotá', 'Bogotá', 'zone-15', 'ZONA CENTRO (LIDER 2)', 'zone-15', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-67', 'Q125', 'Q125 - Bello - Cc Plaza Fabricato', 'Bello', 'zone-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', 'zone-1', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-68', 'Q126', 'Q126 - Ipiales - Centro', 'Ipiales', 'zone-9', 'ZONA NARIÑO', 'zone-9', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-69', 'Q127', 'Q127 - Sabaneta CC Mayorca', 'Sabaneta CC Mayorca', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-70', 'Q128', 'Q128 - Barranquilla cc parque alegra', 'Barranquilla cc parque alegra', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-71', 'Q129', 'Q129 - Bogota-cc plaza de las americas', 'Bogota', 'zone-15', 'ZONA CENTRO (LIDER 2)', 'zone-15', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-72', 'Q131', 'Q131 - Cucuta-CC Jardin Plaza', 'Cucuta', 'zone-6', 'ZONA SANTANDERES', 'zone-6', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-73', 'Q133', 'Q133 -  Popayan-Cc Terra Plaza', 'Popayan', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-74', 'Q134', 'Q134 - Cali - Cc Cosmocentro', 'Cali', 'zone-7', 'ZONA VALLE SUR Y CAUCA', 'zone-7', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-75', 'Q135', 'Q135 - Pasto - Centro', 'Pasto', 'zone-9', 'ZONA NARIÑO', 'zone-9', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-76', 'Q136', 'Q136 - Yopal-Centro', 'Yopal', 'zone-13', 'ZONA CENTRO (LIDER 1)', 'zone-13', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-77', 'Q138', 'Q138 - Manizales - CC Fundadores', 'Manizales', 'zone-8', 'ZONA EJE CAFETERO 1', 'zone-8', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-78', 'Q139', 'Q139 - Armenia - Centro 2', 'Armenia', 'zone-12', 'ZONA EJE CAFETERO 2', 'zone-12', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-79', 'Q140', 'Q140 - Cartagena - CC Mall Plaza', 'Cartagena', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-80', 'Q143', 'Q143 - Sabaneta - CC Mayorca Etapa 1', 'Sabaneta', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-81', 'Q144', 'Q144 - Popayan - Centro 2', 'Popayan', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-82', 'Q145', 'Q145 - Neiva - CC Unicentr', 'Neiva', 'zone-10', 'ZONA TOLHUCA', 'zone-10', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-83', 'Q146', 'Q146 - Palmira - Centro 2', 'Palmira', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-84', 'Q147', 'Q147 - Cali - Cali Mall Plaza', 'Cali', 'zone-7', 'ZONA VALLE SUR Y CAUCA', 'zone-7', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-85', 'Q148', 'Q148 - Medellín - Carabobo Centro', 'Medellín', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-86', 'Q149', 'Q149 - Medellín - Centro', 'Medellín', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-87', 'Q152', 'Q152 - Rionegro - Cc San nicolas', 'Rionegro', 'zone-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', 'zone-1', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-88', 'Q153', 'Q153 - Palmira - CC Llanogrande', 'Palmira', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-89', 'Q154', 'Q154 - Santa Marta - CC Buenavista', 'Santa Marta', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-90', 'Q155', 'Q155 - Bogota - CC Outlet las Americas', 'Bogota', 'zone-15', 'ZONA CENTRO (LIDER 2)', 'zone-15', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-91', 'Q156', 'Q156 - Medellin - CC Santa Fe', 'Medellin', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-92', 'Q157', 'Q157 - Riohacha - CC Viva Wajira', 'Riohacha', 'zone-5', 'ZONA COSTA NORTE', 'zone-5', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-93', 'QST501', 'QST501 - Cali - Plaza Q', 'Cali', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-94', 'QST502', 'QST502 - Cali - Cc Unico 2', 'Cali', 'zone-7', 'ZONA VALLE SUR Y CAUCA', 'zone-7', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-95', 'QST503', 'QST503 - Medellin - Cc Florida', 'Medellin', 'zone-1', 'ZONA ANTIOQUIA Y CASANARE (LIDER 2)', 'zone-1', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-96', 'QST504', 'QST504 - Cali - Cc Jardin Plaza', 'Cali', 'zone-4', 'ZONA CALI 2 Y CAUCA', 'zone-4', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-97', 'QST505', 'QST505 - Tulua - La Herradura', 'Tulua', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-98', 'QST506', 'QST506 - Palmira - CC Llanogrande', 'Palmira', 'zone-3', 'ZONA VALLE CENTRO', 'zone-3', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-99', 'QST508', 'QST508 - Sabaneta - Cc Mayorca', 'Sabaneta', 'zone-14', 'ZONA ANTIOQUIA (LIDER 1)', 'zone-14', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-100', 'QST509', 'QST509 - Cucuta - Cc Jardin Plaza', 'Cucuta', 'zone-6', 'ZONA SANTANDERES', 'zone-6', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;
INSERT INTO pdvs (id, code, name, city, zone_id, zone_name, supervisor_id, opening_hour, closing_hour, allowed_shifts, habitual_schedule)
VALUES ('pdv-101', 'QST510', 'QST510 - YUMBO - CC UNICO', 'YUMBO', 'zone-2', 'ZONA CALI 1', 'zone-2', '10:00', '20:30', '["10:00-20:30","10:00-18:00","11:00-19:00","12:00-20:30","13:00-20:30"]'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, city = EXCLUDED.city, allowed_shifts = EXCLUDED.allowed_shifts;

-- 6.4 Usuarios y Perfiles del Sistema
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-admin', NULL, NULL, '987654321', 'ADMIN-01', 'ADMINISTRADOR GENERAL', 'ADMIN', 'SUPERUSUARIO / ADMIN GENERAL', 'OPERACIONES & AUDITORÍA GLOBAL', 'FIJO', NULL, NULL, 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-thumano', NULL, NULL, '1020304050', 'TH-01', 'TALENTO HUMANO (HR)', 'HR_ADMIN', 'GERENCIA DE TALENTO HUMANO & NÓMINA', 'TALENTO HUMANO', 'FIJO', NULL, NULL, 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-vrx', NULL, NULL, '1081408140', 'VRX-01', 'AUDITORÍA & CONTROL (VRX)', 'AUDITOR_VRX', 'AUDITOR DE CONTROL & COMPLIANCE', 'AUDITORÍA', 'FIJO', NULL, NULL, 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-mantenimiento', NULL, NULL, '1032456789', 'MANT-01', 'ING. CARLOS MENDOZA', 'MAINTENANCE_APPROVER', 'JEFE DE MANTENIMIENTO E INFRAESTRUCTURA', 'MANTENIMIENTO', 'FIJO', NULL, NULL, 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-1', NULL, NULL, '1018456780', 'SUP-zone-1', 'LÍDER ZONA 2', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-1', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-2', NULL, NULL, '1018456781', 'SUP-zone-2', 'LÍDER CALI 1', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-2', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-3', NULL, NULL, '1018456782', 'SUP-zone-3', 'LÍDER VALLE CENTRO', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-3', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-4', NULL, NULL, '1018456783', 'SUP-zone-4', 'LÍDER CALI 2 Y CAUCA', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-4', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-5', NULL, NULL, '1018456784', 'SUP-zone-5', 'LÍDER COSTA NORTE', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-5', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-6', NULL, NULL, '1018456785', 'SUP-zone-6', 'LÍDER SANTANDERES', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-6', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-7', NULL, NULL, '1018456786', 'SUP-zone-7', 'LÍDER VALLE SUR Y CAUCA', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-7', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-8', NULL, NULL, '1018456787', 'SUP-zone-8', 'LÍDER EJE CAFETERO 1', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-8', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-9', NULL, NULL, '1018456788', 'SUP-zone-9', 'LÍDER NARIÑO', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-9', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-10', NULL, NULL, '1018456789', 'SUP-zone-10', 'LÍDER TOLHUCA', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-10', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-11', NULL, NULL, '1018456790', 'SUP-zone-11', 'LÍDER COSTA SUR', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-11', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-12', NULL, NULL, '1018456791', 'SUP-zone-12', 'LÍDER EJE CAFETERO 2', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-12', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-13', NULL, NULL, '1018456792', 'SUP-zone-13', 'LÍDER ZONA 1', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-13', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-14', NULL, NULL, '1018456793', 'SUP-zone-14', 'LÍDER ZONA 1', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-14', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('user-zone-15', NULL, NULL, '1018456794', 'SUP-zone-15', 'LÍDER ZONA 2', 'SUPERVISOR', 'LÍDER DE ZONA', 'RETAIL', 'FIJO', NULL, 'zone-15', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-1', NULL, NULL, '1091678220', '4989', 'DAYANA ANDREA MORENO SANCHEZ', 'EMPLOYEE', 'ADMINISTRADOR(A) PUNTO DE VENTA', 'RETAIL', 'FIJO', 'pdv-1', 'zone-1', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-2', NULL, NULL, '1118816729', '17865', 'RORAIMA QUINTERO OBREDOR', 'EMPLOYEE', 'ASESOR(A) DE IMAGEN', 'RETAIL', 'FIJO', 'pdv-1', 'zone-1', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-3', NULL, NULL, '1005979278', '8519', 'LEIDY LAURA ORTEGA', 'EMPLOYEE', 'ASESOR(A) DE IMAGEN', 'RETAIL', 'FIJO', 'pdv-1', 'zone-1', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-4', NULL, NULL, '1004215413', '14227', 'SANTIAGO CISNEROS DE LA CRUZ', 'EMPLOYEE', 'ASESOR(A) DE IMAGEN', 'RETAIL', 'FIJO', 'pdv-2', 'zone-2', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-5', NULL, NULL, '1005707524', '8687', 'JHOAN SEBASTIAN MOSQUERA MOLINA', 'EMPLOYEE', 'ASESOR(A) DE IMAGEN', 'RETAIL', 'FIJO', 'pdv-2', 'zone-2', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-6', NULL, NULL, '1004236196', '11587', 'DIEGO JULIAN SERRANO CALVACHE', 'EMPLOYEE', 'ADMINISTRADOR(A) PUNTO DE VENTA', 'RETAIL', 'FIJO', 'pdv-2', 'zone-2', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
INSERT INTO users (id, username, password, document_id, code, full_name, role, position, area, contract_type, pdv_id, supervisor_id, weekly_max_hours, is_active)
VALUES ('emp-7', NULL, NULL, '1144163678', '9921', 'IVAN DANIEL SARRIA VIDLA', 'EMPLOYEE', 'ASESOR(A) DE IMAGEN', 'RETAIL', 'FIJO', 'pdv-35', 'zone-2', 42, true)
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, pdv_id = EXCLUDED.pdv_id;
