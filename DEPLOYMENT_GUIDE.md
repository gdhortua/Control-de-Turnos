# Guía de Despliegue: Supabase + GitHub + Vercel

Esta guía te explica paso a paso cómo desplegar el aplicativo **Control de Turnos y Conciliación PDV** en la nube utilizando **Supabase** (Base de Datos PostgreSQL), **GitHub** (Repositorio de Código) y **Vercel** (Alojamiento Frontend).

---

## Paso 1: Configurar la Base de Datos en Supabase

1. Entra a tu cuenta en [Supabase](https://supabase.com/) y entra a tu proyecto (o crea uno nuevo).
2. En el menú lateral izquierdo, haz clic en **SQL Editor** (icono con el símbolo `>_` o terminal).
3. Haz clic en **+ New query**.
4. Abre el archivo `supabase_schema.sql` ubicado en la raíz de este proyecto, copia todo su contenido y pégalo en el editor SQL.
5. Haz clic en el botón verde **Run** (Ejecutar).
   - *Este script crea automáticamente las 9 tablas (`pdvs`, `supervisors`, `users`, `schedules`, `permissions`, `punch_batches`, `punch_records`, `supplementary_justifications`, `app_config`), activa las políticas de seguridad RLS e inserta los 101 PDVs, 15 Zonas regionales y los usuarios del sistema.*
6. Ve a **Project Settings** (icono de engranaje abajo a la izquierda) -> **API**.
7. Copia dos valores esenciales:
   - **Project URL** (ej: `https://abcdefgh.supabase.co`)
   - **Project API Keys (anon / public)** (ej: `eyJhbGciOi...`)

---

## Paso 2: Subir el Código a GitHub

Abre una terminal en la carpeta del proyecto (`control-turnos-pdv`) y ejecuta:

```bash
# 1. Inicializar git
git init

# 2. Agregar todos los archivos
git add .

# 3. Crear el commit
git commit -m "feat: inicializacion arquitectura supabase y vercel"

# 4. Establecer rama principal
git branch -M main

# 5. Conectar con tu repositorio remoto de GitHub (reemplaza con tu URL de GitHub)
git remote add origin https://github.com/TU_USUARIO/control-turnos-pdv.git

# 6. Subir los cambios
git push -u origin main
```

---

## Paso 3: Desplegar en Vercel

1. Entra a [Vercel](https://vercel.com/) e inicia sesión con tu cuenta de GitHub.
2. En el Dashboard, haz clic en **Add New...** -> **Project**.
3. Busca tu repositorio `control-turnos-pdv` y haz clic en **Import**.
4. En la sección **Environment Variables** (Variables de Entorno), agrega las siguientes dos variables:
   - `VITE_SUPABASE_URL` = *(Pega tu Project URL de Supabase)*
   - `VITE_SUPABASE_ANON_KEY` = *(Pega tu Project API Key anon de Supabase)*
5. Haz clic en el botón **Deploy**.

¡Listo! Vercel compilará tu aplicación y te entregará una URL pública y segura (ej: `https://control-turnos-pdv.vercel.app`).
Cada vez que hagas un cambio y lo subas a GitHub (`git push`), Vercel actualizará la aplicación automáticamente.
