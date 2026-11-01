#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generador de scripts JScript para Enterprise Architect
Crea diagramas de robustez ICONIX (Actor, Boundary, Control, Entity)
"""

import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

def generate_jscript(cu_code, cu_title, actors, boundaries, controls, entities, links):
    """
    Genera el código JScript compatible con Enterprise Architect (EA 12 - 16+).
    """
    lines = []
    lines.append('/*')
    lines.append(f' * Enterprise Architect - JScript Automation')
    lines.append(f' * Diagrama de Robustez: {cu_code} - {cu_title}')
    lines.append(f' * Metodologia: ICONIX | Proyecto: SmartLook IA')
    lines.append(' */')
    lines.append('')
    lines.append('function main() {')
    lines.append('\t// 1. Obtener paquete seleccionado en el Project Browser')
    lines.append('\tvar pkg = Repository.GetTreeSelectedPackage();')
    lines.append('\tif (!pkg) {')
    lines.append('\t\tSession.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);')
    lines.append('\t\treturn;')
    lines.append('\t}')
    lines.append('')
    lines.append('\tSession.Output("Iniciando generacion de: ' + cu_code + ' - ' + cu_title + '...");')
    lines.append('')
    lines.append('\t// 2. Crear subpaquete para organizar el Caso de Uso')
    lines.append(f'\tvar subPkg = pkg.Packages.AddNew("{cu_code} - {cu_title}", "");')
    lines.append('\tsubPkg.Update();')
    lines.append('')
    lines.append('\t// 3. Crear Diagrama de Robustez (Tipo Analysis en EA)')
    lines.append(f'\tvar diagram = subPkg.Diagrams.AddNew("Robustez - {cu_code}", "Analysis");')
    lines.append('\tdiagram.Update();')
    lines.append('')
    lines.append('\t// Diccionario de elementos para conectar posteriormente')
    lines.append('\tvar elements = {};')
    lines.append('')
    lines.append('\t// Funcion auxiliar para crear elementos y posicionarlos en el diagrama')
    lines.append('\tfunction addElement(name, type, stereotype, left, top, right, bottom) {')
    lines.append('\t\tvar el = subPkg.Elements.AddNew(name, type);')
    lines.append('\t\tif (stereotype && stereotype !== "") {')
    lines.append('\t\t\tel.Stereotype = stereotype;')
    lines.append('\t\t}')
    lines.append('\t\tel.Update();')
    lines.append('\t\tsubPkg.Elements.Refresh();')
    lines.append('')
    lines.append('\t\tvar diagObj = diagram.DiagramObjects.AddNew("l=" + left + ";r=" + right + ";t=" + top + ";b=" + bottom + ";", "");')
    lines.append('\t\tdiagObj.ElementID = el.ElementID;')
    lines.append('\t\tdiagObj.left = left;')
    lines.append('\t\tdiagObj.right = right;')
    lines.append('\t\tdiagObj.top = top;')
    lines.append('\t\tdiagObj.bottom = bottom;')
    lines.append('\t\tdiagObj.Update();')
    lines.append('\t\treturn el;')
    lines.append('\t}')
    lines.append('')
    lines.append('\t// Funcion auxiliar para conectar elementos')
    lines.append('\tfunction addLink(sourceEl, targetEl, labelText) {')
    lines.append('\t\tif (!sourceEl || !targetEl) return;')
    lines.append('\t\tvar conn = sourceEl.Connectors.AddNew(labelText, "Association");')
    lines.append('\t\tconn.SupplierID = targetEl.ElementID;')
    lines.append('\t\tconn.Direction = "Source -> Destination";')
    lines.append('\t\tconn.Update();')
    lines.append('\t\tsourceEl.Connectors.Refresh();')
    lines.append('\t}')
    lines.append('')

    # Creación de Actores (Columna 1: Left=40, Right=150)
    lines.append('\t// --- COLUMNA 1: ACTORES ---')
    for i, a in enumerate(actors):
        top = -50 - (i * 120)
        bot = top - 80
        lines.append(f'\telements["{a}"] = addElement("{a}", "Actor", "", 40, {top}, 140, {bot});')
    lines.append('')

    # Creación de Fronteras (Columna 2: Left=220, Right=380)
    lines.append('\t// --- COLUMNA 2: FRONTERAS (BOUNDARIES) ---')
    for i, b in enumerate(boundaries):
        top = -50 - (i * 110)
        bot = top - 70
        lines.append(f'\telements["{b}"] = addElement("{b}", "Boundary", "boundary", 220, {top}, 380, {bot});')
    lines.append('')

    # Creación de Controles (Columna 3: Left=460, Right=640)
    lines.append('\t// --- COLUMNA 3: CONTROLES ---')
    for i, c in enumerate(controls):
        top = -50 - (i * 100)
        bot = top - 65
        lines.append(f'\telements["{c}"] = addElement("{c}", "Control", "control", 460, {top}, 650, {bot});')
    lines.append('')

    # Creación de Entidades (Columna 4: Left=740, Right=900)
    lines.append('\t// --- COLUMNA 4: ENTIDADES ---')
    for i, e in enumerate(entities):
        top = -50 - (i * 110)
        bot = top - 70
        # Evitar colisión de nombres entre actor Usuario y entidad Usuario
        key = f"Entity_{e}" if e in actors else e
        lines.append(f'\telements["{key}"] = addElement("{e}", "Entity", "entity", 740, {top}, 900, {bot});')
    lines.append('')

    # Creación de Enlaces
    lines.append('\t// --- ENLACES Y COMUNICACIONES ---')
    for link in links:
        s = link[0]
        t = link[1]
        lbl = link[2] if len(link) > 2 else ""
        if s == 'Usuario':
            s_key = 'Entity_Usuario' if t in controls else 'Usuario'
        else:
            s_key = s
        if t == 'Usuario':
            t_key = 'Entity_Usuario' if s in controls else 'Usuario'
        else:
            t_key = t
        lines.append(f'\taddLink(elements["{s_key}"], elements["{t_key}"], "{lbl}");')
    lines.append('')

    lines.append('\t// 4. Refrescar vistas en Enterprise Architect')
    lines.append('\tdiagram.DiagramObjects.Refresh();')
    lines.append('\tsubPkg.Diagrams.Refresh();')
    lines.append('\tpkg.Packages.Refresh();')
    lines.append('\tRepository.ReloadDiagram(diagram.DiagramID);')
    lines.append(f'\tSession.Output("Diagrama {cu_code} generado con exito.");')
    lines.append('}')
    lines.append('')
    lines.append('main();')

    return '\n'.join(lines)


# ==========================================
# DEFINICIÓN DE LOS 5 CASOS DE USO
# ==========================================

CUS = [
    {
        'code': 'CU01',
        'title': 'Iniciar sesion en el contexto de una empresa',
        'actors': ['Usuario'],
        'boundaries': ['PantallaInicioSesion', 'PantallaPrincipalEmpresa', 'PanelAdminSaaS'],
        'controls': [
            'ControladorAutenticacion',
            'VerificadorCredenciales',
            'VerificadorEstadoEmpresa',
            'ValidadorVigenciaSuscripcion',
            'GeneradorTokenJWT',
            'RegistradorBitacoraAcceso'
        ],
        'entities': ['Usuario', 'Empresa', 'Suscripcion', 'TokenSesion', 'Bitacora'],
        'links': [
            ('Usuario', 'PantallaInicioSesion', 'Ingresa credenciales'),
            ('PantallaInicioSesion', 'ControladorAutenticacion', 'Enviar login'),
            ('ControladorAutenticacion', 'VerificadorCredenciales', 'Verificar clave'),
            ('VerificadorCredenciales', 'Usuario', 'Consultar usuario'),
            ('ControladorAutenticacion', 'VerificadorEstadoEmpresa', 'Verificar empresa activa'),
            ('VerificadorEstadoEmpresa', 'Empresa', 'Consultar empresa'),
            ('ControladorAutenticacion', 'ValidadorVigenciaSuscripcion', 'Verificar vigencia'),
            ('ValidadorVigenciaSuscripcion', 'Suscripcion', 'Consultar suscripcion'),
            ('ControladorAutenticacion', 'GeneradorTokenJWT', 'Generar token'),
            ('GeneradorTokenJWT', 'TokenSesion', 'Crear sesion'),
            ('ControladorAutenticacion', 'RegistradorBitacoraAcceso', 'Registrar log'),
            ('RegistradorBitacoraAcceso', 'Bitacora', 'Guardar acceso'),
            ('ControladorAutenticacion', 'PantallaPrincipalEmpresa', 'Redirigir usuario'),
            ('ControladorAutenticacion', 'PanelAdminSaaS', 'Redirigir SuperAdmin')
        ]
    },
    {
        'code': 'CU02',
        'title': 'Gestionar empresas contratantes',
        'actors': ['Super Administrador'],
        'boundaries': ['PantallaGestionEmpresas', 'FormularioEmpresa', 'DialogoConfirmacionEstado'],
        'controls': [
            'ControladorGestionEmpresas',
            'ValidadorDatosEmpresa',
            'RegistradorEmpresa',
            'RegistradorAdminEmpresa',
            'ActualizadorEstadoEmpresa',
            'ServicioNotificacionCredenciales',
            'RegistradorBitacora'
        ],
        'entities': ['Empresa', 'Usuario', 'Rol', 'Bitacora'],
        'links': [
            ('Super Administrador', 'PantallaGestionEmpresas', 'Selecciona operacion'),
            ('PantallaGestionEmpresas', 'FormularioEmpresa', 'Abrir formulario'),
            ('Super Administrador', 'FormularioEmpresa', 'Ingresa datos'),
            ('FormularioEmpresa', 'ControladorGestionEmpresas', 'Guardar'),
            ('ControladorGestionEmpresas', 'ValidadorDatosEmpresa', 'Validar NIT y email'),
            ('ValidadorDatosEmpresa', 'Empresa', 'Verificar existencia'),
            ('ControladorGestionEmpresas', 'RegistradorEmpresa', 'Crear tenant'),
            ('RegistradorEmpresa', 'Empresa', 'Guardar empresa'),
            ('ControladorGestionEmpresas', 'RegistradorAdminEmpresa', 'Crear admin'),
            ('RegistradorAdminEmpresa', 'Usuario', 'Guardar usuario'),
            ('RegistradorAdminEmpresa', 'Rol', 'Asignar rol'),
            ('ControladorGestionEmpresas', 'ServicioNotificacionCredenciales', 'Enviar correo'),
            ('Super Administrador', 'DialogoConfirmacionEstado', 'Confirmar estado'),
            ('DialogoConfirmacionEstado', 'ControladorGestionEmpresas', 'Aplicar cambio'),
            ('ControladorGestionEmpresas', 'ActualizadorEstadoEmpresa', 'Modificar estado'),
            ('ActualizadorEstadoEmpresa', 'Empresa', 'Actualizar BD'),
            ('ControladorGestionEmpresas', 'RegistradorBitacora', 'Registrar log'),
            ('RegistradorBitacora', 'Bitacora', 'Guardar accion'),
            ('ControladorGestionEmpresas', 'PantallaGestionEmpresas', 'Actualizar lista')
        ]
    },
    {
        'code': 'CU03',
        'title': 'Gestionar planes de suscripcion',
        'actors': ['Super Administrador'],
        'boundaries': ['PantallaGestionPlanes', 'FormularioPlan'],
        'controls': [
            'ControladorGestionPlanes',
            'ValidadorParametrosPlan',
            'VerificadorImpactoEmpresas',
            'PersistidorPlan',
            'AsignadorFuncionalidadesPlan',
            'RegistradorBitacora'
        ],
        'entities': ['Plan', 'Funcionalidad', 'Empresa', 'Bitacora'],
        'links': [
            ('Super Administrador', 'PantallaGestionPlanes', 'Consultar planes'),
            ('PantallaGestionPlanes', 'FormularioPlan', 'Abrir formulario'),
            ('Super Administrador', 'FormularioPlan', 'Editar limites'),
            ('FormularioPlan', 'ControladorGestionPlanes', 'Guardar plan'),
            ('ControladorGestionPlanes', 'ValidadorParametrosPlan', 'Validar limites'),
            ('ControladorGestionPlanes', 'VerificadorImpactoEmpresas', 'Verificar empresas activas'),
            ('VerificadorImpactoEmpresas', 'Empresa', 'Consultar sucursales'),
            ('ControladorGestionPlanes', 'PersistidorPlan', 'Guardar plan'),
            ('PersistidorPlan', 'Plan', 'Actualizar plan'),
            ('ControladorGestionPlanes', 'AsignadorFuncionalidadesPlan', 'Asignar funciones'),
            ('AsignadorFuncionalidadesPlan', 'Funcionalidad', 'Guardar funciones'),
            ('ControladorGestionPlanes', 'RegistradorBitacora', 'Registrar log'),
            ('RegistradorBitacora', 'Bitacora', 'Guardar accion'),
            ('ControladorGestionPlanes', 'PantallaGestionPlanes', 'Actualizar lista')
        ]
    },
    {
        'code': 'CU04',
        'title': 'Gestionar suscripcion de una empresa',
        'actors': ['Super Administrador', 'Administrador de Empresa'],
        'boundaries': ['PantallaSuscripcionEmpresa', 'FormularioAsignacionPlan', 'PantallaMiSuscripcion'],
        'controls': [
            'ControladorSuscripciones',
            'ConsultorCatalogoPlanes',
            'CalculadorFechaVencimiento',
            'ValidadorCapacidadSucursales',
            'ActualizadorSuscripcion',
            'ExtensorVigenciaSuscripcion',
            'RegistradorBitacora'
        ],
        'entities': ['Empresa', 'Plan', 'Suscripcion', 'Sucursal', 'Bitacora'],
        'links': [
            ('Super Administrador', 'PantallaSuscripcionEmpresa', 'Consultar suscripcion'),
            ('PantallaSuscripcionEmpresa', 'ControladorSuscripciones', 'Cargar datos'),
            ('ControladorSuscripciones', 'Suscripcion', 'Consultar suscripcion actual'),
            ('PantallaSuscripcionEmpresa', 'FormularioAsignacionPlan', 'Asignar o renovar'),
            ('ControladorSuscripciones', 'ConsultorCatalogoPlanes', 'Listar planes'),
            ('ConsultorCatalogoPlanes', 'Plan', 'Obtener planes'),
            ('Super Administrador', 'FormularioAsignacionPlan', 'Seleccionar plan'),
            ('FormularioAsignacionPlan', 'ControladorSuscripciones', 'Confirmar asignacion'),
            ('ControladorSuscripciones', 'CalculadorFechaVencimiento', 'Calcular vencimiento'),
            ('ControladorSuscripciones', 'ValidadorCapacidadSucursales', 'Validar limite sucursales'),
            ('ValidadorCapacidadSucursales', 'Sucursal', 'Contar sucursales'),
            ('ControladorSuscripciones', 'ActualizadorSuscripcion', 'Crear nueva suscripcion'),
            ('ActualizadorSuscripcion', 'Suscripcion', 'Guardar suscripcion'),
            ('ControladorSuscripciones', 'ExtensorVigenciaSuscripcion', 'Extender vigencia'),
            ('ExtensorVigenciaSuscripcion', 'Suscripcion', 'Actualizar fecha'),
            ('ControladorSuscripciones', 'RegistradorBitacora', 'Registrar log'),
            ('RegistradorBitacora', 'Bitacora', 'Guardar accion'),
            ('Administrador de Empresa', 'PantallaMiSuscripcion', 'Consultar mi suscripcion'),
            ('PantallaMiSuscripcion', 'ControladorSuscripciones', 'Cargar modo lectura'),
            ('ControladorSuscripciones', 'PantallaMiSuscripcion', 'Mostrar datos')
        ]
    },
    {
        'code': 'CU05',
        'title': 'Verificar plan y limites de la suscripcion',
        'actors': ['Sistema Backend'],
        'boundaries': ['InterceptorPeticionAPI'],
        'controls': [
            'ControladorVerificacionPlan',
            'ExtractorTenantToken',
            'VerificadorVigenciaSuscripcion',
            'VerificadorFuncionalidadHabilitada',
            'ContadorRecursosConsumidos',
            'ValidadorTopeRecurso',
            'GeneradorRespuestaAutorizacion'
        ],
        'entities': ['TokenSesion', 'Empresa', 'Suscripcion', 'Plan', 'Funcionalidad', 'Sucursal'],
        'links': [
            ('Sistema Backend', 'InterceptorPeticionAPI', 'Recibe peticion'),
            ('InterceptorPeticionAPI', 'ControladorVerificacionPlan', 'Validar permisos'),
            ('ControladorVerificacionPlan', 'ExtractorTenantToken', 'Extraer token'),
            ('ExtractorTenantToken', 'TokenSesion', 'Leer payload'),
            ('ControladorVerificacionPlan', 'VerificadorVigenciaSuscripcion', 'Validar vigencia'),
            ('VerificadorVigenciaSuscripcion', 'Suscripcion', 'Consultar estado'),
            ('ControladorVerificacionPlan', 'VerificadorFuncionalidadHabilitada', 'Validar funcionalidad'),
            ('VerificadorFuncionalidadHabilitada', 'Plan', 'Consultar permisos del plan'),
            ('Plan', 'Funcionalidad', 'Verificar funcionalidad activa'),
            ('ControladorVerificacionPlan', 'ContadorRecursosConsumidos', 'Contar recursos usados'),
            ('ContadorRecursosConsumidos', 'Sucursal', 'Contar sucursales'),
            ('ControladorVerificacionPlan', 'ValidadorTopeRecurso', 'Comparar vs limite'),
            ('ControladorVerificacionPlan', 'GeneradorRespuestaAutorizacion', 'Generar respuesta'),
            ('GeneradorRespuestaAutorizacion', 'InterceptorPeticionAPI', 'Autorizar o rechazar')
        ]
    }
]

for cu in CUS:
    code_content = generate_jscript(
        cu['code'], cu['title'], cu['actors'], cu['boundaries'],
        cu['controls'], cu['entities'], cu['links']
    )
    fname = f"{cu['code']}_Robustez_EA.js"
    fpath = os.path.join(OUTPUT_DIR, fname)
    with open(fpath, 'w', encoding='utf-8') as f:
        f.write(code_content)
    print("Generado JScript:", fpath)

print("Todos los scripts JScript han sido generados exitosamente.")
