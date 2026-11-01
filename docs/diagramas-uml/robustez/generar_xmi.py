#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generador de Diagramas de Robustez (ICONIX) en formato XMI 2.1 para Enterprise Architect
SmartLook IA - Sistemas de Información II (Grupo 28)
"""

import os
import uuid
import datetime

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

def uid(name):
    # Genera un GUID determinista o único pero con formato EA
    return f"EAID_{uuid.uuid5(uuid.NAMESPACE_DNS, name).hex.upper()[:16]}"

def create_xmi_file(filepath, pkg_name, use_cases):
    """
    Genera un archivo XMI 2.1 estándar totalmente compatible con Sparx Enterprise Architect.
    """
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # XML Header
    xml = []
    xml.append('<?xml version="1.0" encoding="windows-1252"?>')
    xml.append('<xmi:XMI xmi:version="2.1" xmlns:uml="http://schema.omg.org/spec/UML/2.1" xmlns:xmi="http://schema.omg.org/spec/XMI/2.1">')
    xml.append('\t<xmi:Documentation exporter="Enterprise Architect" exporterVersion="6.5"/>')
    xml.append('\t<uml:Model xmi:type="uml:Model" name="EA_Model" xmi:id="MX_EA_Model">')
    
    pkg_id = uid(pkg_name)
    xml.append(f'\t\t<packagedElement xmi:type="uml:Package" xmi:id="{pkg_id}" name="{pkg_name}">')

    # Almacén para extensiones de EA
    all_elements = []
    all_connectors = []
    all_diagrams = []

    for cu in use_cases:
        cu_code = cu['code']
        cu_title = cu['title']
        subpkg_name = f"{cu_code} - {cu_title}"
        subpkg_id = uid(subpkg_name)
        
        xml.append(f'\t\t\t<packagedElement xmi:type="uml:Package" xmi:id="{subpkg_id}" name="{subpkg_name}">')
        
        # Elementos del CU
        diag_elements = []
        
        # 1. Actores
        for act in cu['actors']:
            el_id = uid(f"{cu_code}_act_{act}")
            xml.append(f'\t\t\t\t<packagedElement xmi:type="uml:Actor" xmi:id="{el_id}" name="{act}"/>')
            all_elements.append({
                'id': el_id, 'name': act, 'type': 'Actor', 'stereotype': '', 'package_id': subpkg_id
            })
            diag_elements.append(el_id)
            
        # 2. Boundaries
        for b in cu['boundaries']:
            el_id = uid(f"{cu_code}_b_{b}")
            xml.append(f'\t\t\t\t<packagedElement xmi:type="uml:Class" xmi:id="{el_id}" name="{b}"/>')
            all_elements.append({
                'id': el_id, 'name': b, 'type': 'Boundary', 'stereotype': 'boundary', 'package_id': subpkg_id
            })
            diag_elements.append(el_id)

        # 3. Controls
        for c in cu['controls']:
            el_id = uid(f"{cu_code}_c_{c}")
            xml.append(f'\t\t\t\t<packagedElement xmi:type="uml:Class" xmi:id="{el_id}" name="{c}"/>')
            all_elements.append({
                'id': el_id, 'name': c, 'type': 'Control', 'stereotype': 'control', 'package_id': subpkg_id
            })
            diag_elements.append(el_id)

        # 4. Entities
        for e in cu['entities']:
            el_id = uid(f"{cu_code}_e_{e}")
            xml.append(f'\t\t\t\t<packagedElement xmi:type="uml:Class" xmi:id="{el_id}" name="{e}"/>')
            all_elements.append({
                'id': el_id, 'name': e, 'type': 'Entity', 'stereotype': 'entity', 'package_id': subpkg_id
            })
            diag_elements.append(el_id)

        # 5. Conectores / Enlaces de robustez
        for conn in cu['links']:
            source_name = conn[0]
            target_name = conn[1]
            desc = conn[2] if len(conn) > 2 else ""
            
            # Resolver IDs distinguiendo por tipo (Actor vs Entidad)
            def find_id(name, is_source, other):
                matches = [el for el in all_elements if el['package_id'] == subpkg_id and el['name'] == name]
                if not matches:
                    return None
                if len(matches) == 1:
                    return matches[0]['id']
                # Si hay ambigüedad (ej: Actor 'Usuario' vs Entidad 'Usuario')
                if name in cu['actors'] and (is_source or other in cu['boundaries']):
                    for m in matches:
                        if m['type'] == 'Actor':
                            return m['id']
                if name in cu['entities']:
                    for m in matches:
                        if m['type'] == 'Entity':
                            return m['id']
                return matches[0]['id']

            s_id = find_id(source_name, True, target_name)
            t_id = find_id(target_name, False, source_name)
            
            if s_id and t_id:
                conn_id = uid(f"{cu_code}_conn_{source_name}_{target_name}_{desc}")
                xml.append(f'\t\t\t\t<packagedElement xmi:type="uml:Association" xmi:id="{conn_id}" name="{desc}">')
                xml.append(f'\t\t\t\t\t<memberEnd xmi:idref="{s_id}"/>')
                xml.append(f'\t\t\t\t\t<memberEnd xmi:idref="{t_id}"/>')
                xml.append('\t\t\t\t</packagedElement>')
                all_connectors.append({
                    'id': conn_id, 'source_id': s_id, 'target_id': t_id, 'name': desc, 'type': 'Association'
                })

        diag_id = uid(f"{cu_code}_diagram")
        all_diagrams.append({
            'id': diag_id,
            'package_id': subpkg_id,
            'name': f"Diagrama de Robustez - {cu_code}",
            'elements': diag_elements
        })

        xml.append('\t\t\t</packagedElement>') # Cierre subpkg

    xml.append('\t\t</packagedElement>') # Cierre pkg principal
    xml.append('\t</uml:Model>')

    # Sección de Extensiones Enterprise Architect
    xml.append('\t<xmi:Extension extender="Enterprise Architect" extenderID="6.5">')
    
    # 1. Elements
    xml.append('\t\t<elements>')
    for el in all_elements:
        st_xml = f' stereotype="{el["stereotype"]}"' if el["stereotype"] else ''
        xml.append(f'\t\t\t<element xmi:idref="{el["id"]}" xmi:type="uml:{el["type"]}" name="{el["name"]}" scope="public"{st_xml}>')
        xml.append(f'\t\t\t\t<model package="{el["package_id"]}" tpos="0" ea_localid="0" ea_eleType="element"/>')
        xml.append(f'\t\t\t\t<properties isSpecification="false" sType="{el["type"]}" nType="0" scope="public"{st_xml}/>')
        xml.append('\t\t\t</element>')
    xml.append('\t\t</elements>')

    # 2. Connectors
    xml.append('\t\t<connectors>')
    for conn in all_connectors:
        xml.append(f'\t\t\t<connector xmi:idref="{conn["id"]}">')
        xml.append(f'\t\t\t\t<source xmi:idref="{conn["source_id"]}"/>')
        xml.append(f'\t\t\t\t<target xmi:idref="{conn["target_id"]}"/>')
        xml.append(f'\t\t\t\t<properties ea_type="{conn["type"]}" direction="Source -&gt; Destination"/>')
        if conn["name"]:
            xml.append(f'\t\t\t\t<labels mb="{conn["name"]}"/>')
        xml.append('\t\t\t</connector>')
    xml.append('\t\t</connectors>')

    # 3. Diagrams
    xml.append('\t\t<diagrams>')
    for diag in all_diagrams:
        xml.append(f'\t\t\t<diagram xmi:id="{diag["id"]}">')
        xml.append('\t\t\t\t<model package="{}" ea_localid="0"/>'.format(diag['package_id']))
        xml.append(f'\t\t\t\t<properties name="{diag["name"]}" type="Analysis"/>')
        xml.append(f'\t\t\t\t<project author="SmartLook IA" version="1.0" created="{now}" modified="{now}"/>')
        xml.append('\t\t\t\t<elements>')
        
        # Distribución automática en cuadrícula de coordenadas para EA
        x = 50
        y = 50
        for i, el_id in enumerate(diag['elements']):
            left = x + (i % 4) * 220
            top = y + (i // 4) * 140
            right = left + 140
            bottom = top + 80
            xml.append(f'\t\t\t\t\t<element subject="{el_id}" seq="{i+1}" style="DUID={el_id[:8]};L={left};T={top};R={right};B={bottom};"/>')
        
        xml.append('\t\t\t\t</elements>')
        xml.append('\t\t\t</diagram>')
    xml.append('\t\t</diagrams>')

    xml.append('\t</xmi:Extension>')
    xml.append('</xmi:XMI>')

    with open(filepath, 'w', encoding='windows-1252') as f:
        f.write('\n'.join(xml))
    print(f"Generado exitosamente: {filepath}")


# ==========================================
# DEFINICIÓN DE LOS 5 CASOS DE USO (ICONIX)
# ==========================================

CU01 = {
    'code': 'CU01',
    'title': 'Iniciar sesion en el contexto de una empresa',
    'actors': ['Usuario'],
    'boundaries': [
        'PantallaInicioSesion',
        'PantallaPrincipalEmpresa',
        'PanelAdminSaaS'
    ],
    'controls': [
        'ControladorAutenticacion',
        'VerificadorCredenciales',
        'VerificadorEstadoEmpresa',
        'ValidadorVigenciaSuscripcion',
        'GeneradorTokenJWT',
        'RegistradorBitacoraAcceso'
    ],
    'entities': [
        'Usuario',
        'Empresa',
        'Suscripcion',
        'TokenSesion',
        'Bitacora'
    ],
    'links': [
        ('Usuario', 'PantallaInicioSesion', 'Ingresa credenciales'),
        ('PantallaInicioSesion', 'ControladorAutenticacion', 'Enviar credenciales'),
        ('ControladorAutenticacion', 'VerificadorCredenciales', 'Solicitar verificacion'),
        ('VerificadorCredenciales', 'Usuario', 'Consultar hash y estado'),
        ('ControladorAutenticacion', 'VerificadorEstadoEmpresa', 'Verificar tenant activo'),
        ('VerificadorEstadoEmpresa', 'Empresa', 'Consultar estado empresa'),
        ('ControladorAutenticacion', 'ValidadorVigenciaSuscripcion', 'Verificar suscripcion vigente'),
        ('ValidadorVigenciaSuscripcion', 'Suscripcion', 'Consultar vigencia'),
        ('ControladorAutenticacion', 'GeneradorTokenJWT', 'Generar token con tenant_id y rol'),
        ('GeneradorTokenJWT', 'TokenSesion', 'Crear token'),
        ('ControladorAutenticacion', 'RegistradorBitacoraAcceso', 'Auditar acceso'),
        ('RegistradorBitacoraAcceso', 'Bitacora', 'Guardar log de sesion'),
        ('ControladorAutenticacion', 'PantallaPrincipalEmpresa', 'Redirigir a panel tenant'),
        ('ControladorAutenticacion', 'PanelAdminSaaS', 'Redirigir SuperAdmin')
    ]
}

CU02 = {
    'code': 'CU02',
    'title': 'Gestionar empresas contratantes',
    'actors': ['Super Administrador'],
    'boundaries': [
        'PantallaGestionEmpresas',
        'FormularioEmpresa',
        'DialogoConfirmacionEstado'
    ],
    'controls': [
        'ControladorGestionEmpresas',
        'ValidadorDatosEmpresa',
        'RegistradorEmpresa',
        'RegistradorAdminEmpresa',
        'ActualizadorEstadoEmpresa',
        'ServicioNotificacionCredenciales',
        'RegistradorBitacora'
    ],
    'entities': [
        'Empresa',
        'Usuario',
        'Rol',
        'Bitacora'
    ],
    'links': [
        ('Super Administrador', 'PantallaGestionEmpresas', 'Selecciona operacion'),
        ('PantallaGestionEmpresas', 'FormularioEmpresa', 'Abrir formulario'),
        ('Super Administrador', 'FormularioEmpresa', 'Ingresa datos empresa y admin'),
        ('FormularioEmpresa', 'ControladorGestionEmpresas', 'Enviar formulario'),
        ('ControladorGestionEmpresas', 'ValidadorDatosEmpresa', 'Validar NIT y email unicos'),
        ('ValidadorDatosEmpresa', 'Empresa', 'Verificar duplicados'),
        ('ControladorGestionEmpresas', 'RegistradorEmpresa', 'Crear nuevo tenant'),
        ('RegistradorEmpresa', 'Empresa', 'Insertar empresa activa'),
        ('ControladorGestionEmpresas', 'RegistradorAdminEmpresa', 'Crear usuario administrador'),
        ('RegistradorAdminEmpresa', 'Usuario', 'Insertar usuario tenant'),
        ('RegistradorAdminEmpresa', 'Rol', 'Asignar rol Administrador'),
        ('ControladorGestionEmpresas', 'ServicioNotificacionCredenciales', 'Enviar correo bienvenida'),
        ('Super Administrador', 'DialogoConfirmacionEstado', 'Confirmar suspender/reactivar'),
        ('DialogoConfirmacionEstado', 'ControladorGestionEmpresas', 'Ejecutar cambio de estado'),
        ('ControladorGestionEmpresas', 'ActualizadorEstadoEmpresa', 'Cambiar estado tenant'),
        ('ActualizadorEstadoEmpresa', 'Empresa', 'Actualizar estado en BD'),
        ('ControladorGestionEmpresas', 'RegistradorBitacora', 'Auditar accion'),
        ('RegistradorBitacora', 'Bitacora', 'Guardar log en bitacora'),
        ('ControladorGestionEmpresas', 'PantallaGestionEmpresas', 'Refrescar listado')
    ]
}

CU03 = {
    'code': 'CU03',
    'title': 'Gestionar planes de suscripcion',
    'actors': ['Super Administrador'],
    'boundaries': [
        'PantallaGestionPlanes',
        'FormularioPlan'
    ],
    'controls': [
        'ControladorGestionPlanes',
        'ValidadorParametrosPlan',
        'VerificadorImpactoEmpresas',
        'PersistidorPlan',
        'AsignadorFuncionalidadesPlan',
        'RegistradorBitacora'
    ],
    'entities': [
        'Plan',
        'Funcionalidad',
        'Empresa',
        'Bitacora'
    ],
    'links': [
        ('Super Administrador', 'PantallaGestionPlanes', 'Consulta catalogo de planes'),
        ('PantallaGestionPlanes', 'FormularioPlan', 'Abrir edicion o creacion'),
        ('Super Administrador', 'FormularioPlan', 'Modifica limites y funciones'),
        ('FormularioPlan', 'ControladorGestionPlanes', 'Guardar cambios'),
        ('ControladorGestionPlanes', 'ValidadorParametrosPlan', 'Validar limite sucursales > 0'),
        ('ControladorGestionPlanes', 'VerificadorImpactoEmpresas', 'Verificar empresas suscritas'),
        ('VerificadorImpactoEmpresas', 'Empresa', 'Consultar sucursales activas'),
        ('ControladorGestionPlanes', 'PersistidorPlan', 'Guardar datos de plan'),
        ('PersistidorPlan', 'Plan', 'Insertar/Actualizar plan'),
        ('ControladorGestionPlanes', 'AsignadorFuncionalidadesPlan', 'Vincular funcionalidades'),
        ('AsignadorFuncionalidadesPlan', 'Funcionalidad', 'Guardar relacion plan-funcionalidad'),
        ('ControladorGestionPlanes', 'RegistradorBitacora', 'Auditar cambios'),
        ('RegistradorBitacora', 'Bitacora', 'Guardar log'),
        ('ControladorGestionPlanes', 'PantallaGestionPlanes', 'Mostrar lista actualizada')
    ]
}

CU04 = {
    'code': 'CU04',
    'title': 'Gestionar suscripcion de una empresa',
    'actors': [
        'Super Administrador',
        'Administrador de Empresa'
    ],
    'boundaries': [
        'PantallaSuscripcionEmpresa',
        'FormularioAsignacionPlan',
        'PantallaMiSuscripcion'
    ],
    'controls': [
        'ControladorSuscripciones',
        'ConsultorCatalogoPlanes',
        'CalculadorFechaVencimiento',
        'ValidadorCapacidadSucursales',
        'ActualizadorSuscripcion',
        'ExtensorVigenciaSuscripcion',
        'RegistradorBitacora'
    ],
    'entities': [
        'Empresa',
        'Plan',
        'Suscripcion',
        'Sucursal',
        'Bitacora'
    ],
    'links': [
        ('Super Administrador', 'PantallaSuscripcionEmpresa', 'Abre suscripcion de empresa'),
        ('PantallaSuscripcionEmpresa', 'ControladorSuscripciones', 'Consultar estado e historial'),
        ('ControladorSuscripciones', 'Suscripcion', 'Obtener suscripcion vigente e historial'),
        ('PantallaSuscripcionEmpresa', 'FormularioAsignacionPlan', 'Presiona Asignar plan o Renovar'),
        ('ControladorSuscripciones', 'ConsultorCatalogoPlanes', 'Obtener planes disponibles'),
        ('ConsultorCatalogoPlanes', 'Plan', 'Consultar planes'),
        ('Super Administrador', 'FormularioAsignacionPlan', 'Selecciona plan y fecha inicio'),
        ('FormularioAsignacionPlan', 'ControladorSuscripciones', 'Enviar asignacion'),
        ('ControladorSuscripciones', 'CalculadorFechaVencimiento', 'Calcular vencimiento por duracion'),
        ('ControladorSuscripciones', 'ValidadorCapacidadSucursales', 'Validar sucursales activas vs limite'),
        ('ValidadorCapacidadSucursales', 'Sucursal', 'Contar sucursales activas del tenant'),
        ('ControladorSuscripciones', 'ActualizadorSuscripcion', 'Cerrar anterior y crear nueva'),
        ('ActualizadorSuscripcion', 'Suscripcion', 'Insertar nueva suscripcion vigente'),
        ('ControladorSuscripciones', 'ExtensorVigenciaSuscripcion', 'Extender fecha si es renovacion'),
        ('ControladorSuscripciones', 'RegistradorBitacora', 'Auditar transaccion'),
        ('RegistradorBitacora', 'Bitacora', 'Guardar log en bitacora'),
        ('Administrador de Empresa', 'PantallaMiSuscripcion', 'Consulta estado en modo lectura'),
        ('PantallaMiSuscripcion', 'ControladorSuscripciones', 'Solicitar datos de suscripcion propia'),
        ('ControladorSuscripciones', 'PantallaMiSuscripcion', 'Mostrar plan, limites y dias restantes')
    ]
}

CU05 = {
    'code': 'CU05',
    'title': 'Verificar plan y limites de la suscripcion',
    'actors': ['Sistema Backend'],
    'boundaries': [
        'InterceptorPeticionAPI'
    ],
    'controls': [
        'ControladorVerificacionPlan',
        'ExtractorTenantToken',
        'VerificadorVigenciaSuscripcion',
        'VerificadorFuncionalidadHabilitada',
        'ContadorRecursosConsumidos',
        'ValidadorTopeRecurso',
        'GeneradorRespuestaAutorizacion'
    ],
    'entities': [
        'TokenSesion',
        'Empresa',
        'Suscripcion',
        'Plan',
        'Funcionalidad',
        'Sucursal'
    ],
    'links': [
        ('Sistema Backend', 'InterceptorPeticionAPI', 'Recibe peticion autenticada'),
        ('InterceptorPeticionAPI', 'ControladorVerificacionPlan', 'Solicita autorizacion de operacion'),
        ('ControladorVerificacionPlan', 'ExtractorTenantToken', 'Extraer tenant_id y roles'),
        ('ExtractorTenantToken', 'TokenSesion', 'Decodificar JWT'),
        ('ControladorVerificacionPlan', 'VerificadorVigenciaSuscripcion', 'Validar fecha vencimiento'),
        ('VerificadorVigenciaSuscripcion', 'Suscripcion', 'Consultar vigencia de empresa'),
        ('ControladorVerificacionPlan', 'VerificadorFuncionalidadHabilitada', 'Validar permiso funcional'),
        ('VerificadorFuncionalidadHabilitada', 'Plan', 'Consultar plan contratado'),
        ('Plan', 'Funcionalidad', 'Verificar si funcionalidad esta activa'),
        ('ControladorVerificacionPlan', 'ContadorRecursosConsumidos', 'Contar sucursales si aplica'),
        ('ContadorRecursosConsumidos', 'Sucursal', 'Contar sucursales activas'),
        ('ControladorVerificacionPlan', 'ValidadorTopeRecurso', 'Comparar sucursales vs limite_sucursales'),
        ('ControladorVerificacionPlan', 'GeneradorRespuestaAutorizacion', 'Generar resultado autorizacion'),
        ('GeneradorRespuestaAutorizacion', 'InterceptorPeticionAPI', 'Retornar OK o mensaje de bloqueo')
    ]
}

if __name__ == '__main__':
    all_cus = [CU01, CU02, CU03, CU04, CU05]
    
    # 1. Generar paquete consolidado
    consolidated_path = os.path.join(OUTPUT_DIR, "Paquete1_Robustez_CU01_a_CU05.xmi")
    create_xmi_file(consolidated_path, "Diagramas de Robustez - Paquete 1 SaaS Multitenant", all_cus)
    
    # 2. Generar individuales
    for cu in all_cus:
        file_path = os.path.join(OUTPUT_DIR, f"{cu['code']}_Robustez.xmi")
        create_xmi_file(file_path, f"Robustez {cu['code']} - {cu['title']}", [cu])

    print("Todos los archivos XMI 2.1 han sido generados en:", OUTPUT_DIR)
