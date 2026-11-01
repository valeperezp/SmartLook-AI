/*
 * Enterprise Architect - JScript Automation Consolidado
 * Diagramas de Robustez: CU01 al CU05 (Paquete 1 - SaaS Multitenant)
 * Metodologia: ICONIX | Proyecto: SmartLook IA
 */

function main() {
    var pkg = Repository.GetTreeSelectedPackage();
    if (!pkg) {
        Session.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);
        return;
    }

    Session.Output("==================================================");
    Session.Output("Iniciando generacion de Robustez (CU01 a CU05)...");
    Session.Output("==================================================");

    var mainPkg = pkg.Packages.AddNew("Paquete 1 - SaaS Multitenant (Robustez)", "");
    mainPkg.Update();

    function createDiagramForCU(cuCode, cuTitle, actors, boundaries, controls, entities, links) {
        var subPkg = mainPkg.Packages.AddNew(cuCode + " - " + cuTitle, "");
        subPkg.Update();

        var diagram = subPkg.Diagrams.AddNew("Robustez - " + cuCode, "Analysis");
        diagram.Update();

        var elements = {};

        function addElement(name, type, stereotype, left, top, right, bottom) {
            var el = subPkg.Elements.AddNew(name, type);
            if (stereotype && stereotype !== "") {
                el.Stereotype = stereotype;
            }
            el.Update();
            subPkg.Elements.Refresh();

            var diagObj = diagram.DiagramObjects.AddNew("l=" + left + ";r=" + right + ";t=" + top + ";b=" + bottom + ";", "");
            diagObj.ElementID = el.ElementID;
            diagObj.left = left;
            diagObj.right = right;
            diagObj.top = top;
            diagObj.bottom = bottom;
            diagObj.Update();
            return el;
        }

        function addLink(sourceEl, targetEl, labelText) {
            if (!sourceEl || !targetEl) return;
            var conn = sourceEl.Connectors.AddNew(labelText, "Association");
            conn.SupplierID = targetEl.ElementID;
            conn.Direction = "Source -> Destination";
            conn.Update();
            sourceEl.Connectors.Refresh();
        }

        // Columna 1: Actores
        for (var i = 0; i < actors.length; i++) {
            var a = actors[i];
            var top = -50 - (i * 120);
            elements[a] = addElement(a, "Actor", "", 40, top, 140, top - 80);
        }

        // Columna 2: Fronteras
        for (var i = 0; i < boundaries.length; i++) {
            var b = boundaries[i];
            var top = -50 - (i * 110);
            elements[b] = addElement(b, "Boundary", "boundary", 220, top, 380, top - 70);
        }

        // Columna 3: Controles
        for (var i = 0; i < controls.length; i++) {
            var c = controls[i];
            var top = -50 - (i * 95);
            elements[c] = addElement(c, "Control", "control", 460, top, 650, top - 65);
        }

        // Columna 4: Entidades
        for (var i = 0; i < entities.length; i++) {
            var e = entities[i];
            var top = -50 - (i * 110);
            var isHomonym = false;
            for (var a = 0; a < actors.length; a++) {
                if (actors[a] === e) isHomonym = true;
            }
            var key = isHomonym ? "Entity_" + e : e;
            elements[key] = addElement(e, "Entity", "entity", 740, top, 900, top - 70);
        }

        // Enlaces
        for (var i = 0; i < links.length; i++) {
            var s = links[i][0];
            var t = links[i][1];
            var lbl = links[i][2] || "";
            
            var sKey = s;
            var tKey = t;
            if (s === "Usuario") {
                var isCtrl = false;
                for (var c = 0; c < controls.length; c++) if (controls[c] === t) isCtrl = true;
                sKey = isCtrl ? "Entity_Usuario" : "Usuario";
            }
            if (t === "Usuario") {
                var isCtrl = false;
                for (var c = 0; c < controls.length; c++) if (controls[c] === s) isCtrl = true;
                tKey = isCtrl ? "Entity_Usuario" : "Usuario";
            }
            addLink(elements[sKey], elements[tKey], lbl);
        }

        diagram.DiagramObjects.Refresh();
        subPkg.Diagrams.Refresh();
        Repository.ReloadDiagram(diagram.DiagramID);
        Session.Output("-> Generado " + cuCode + ": " + cuTitle);
    }

    // CU01
    createDiagramForCU(
        "CU01", "Iniciar sesion en el contexto de una empresa",
        ["Usuario"],
        ["PantallaInicioSesion", "PantallaPrincipalEmpresa", "PanelAdminSaaS"],
        ["ControladorAutenticacion", "VerificadorCredenciales", "VerificadorEstadoEmpresa", "ValidadorVigenciaSuscripcion", "GeneradorTokenJWT", "RegistradorBitacoraAcceso"],
        ["Usuario", "Empresa", "Suscripcion", "TokenSesion", "Bitacora"],
        [
            ["Usuario", "PantallaInicioSesion", "Ingresa credenciales"],
            ["PantallaInicioSesion", "ControladorAutenticacion", "Enviar login"],
            ["ControladorAutenticacion", "VerificadorCredenciales", "Verificar clave"],
            ["VerificadorCredenciales", "Usuario", "Consultar usuario"],
            ["ControladorAutenticacion", "VerificadorEstadoEmpresa", "Verificar empresa activa"],
            ["VerificadorEstadoEmpresa", "Empresa", "Consultar empresa"],
            ["ControladorAutenticacion", "ValidadorVigenciaSuscripcion", "Verificar vigencia"],
            ["ValidadorVigenciaSuscripcion", "Suscripcion", "Consultar suscripcion"],
            ["ControladorAutenticacion", "GeneradorTokenJWT", "Generar token"],
            ["GeneradorTokenJWT", "TokenSesion", "Crear sesion"],
            ["ControladorAutenticacion", "RegistradorBitacoraAcceso", "Registrar log"],
            ["RegistradorBitacoraAcceso", "Bitacora", "Guardar acceso"],
            ["ControladorAutenticacion", "PantallaPrincipalEmpresa", "Redirigir usuario"],
            ["ControladorAutenticacion", "PanelAdminSaaS", "Redirigir SuperAdmin"]
        ]
    );

    // CU02
    createDiagramForCU(
        "CU02", "Gestionar empresas contratantes",
        ["Super Administrador"],
        ["PantallaGestionEmpresas", "FormularioEmpresa", "DialogoConfirmacionEstado"],
        ["ControladorGestionEmpresas", "ValidadorDatosEmpresa", "RegistradorEmpresa", "RegistradorAdminEmpresa", "ActualizadorEstadoEmpresa", "ServicioNotificacionCredenciales", "RegistradorBitacora"],
        ["Empresa", "Usuario", "Rol", "Bitacora"],
        [
            ["Super Administrador", "PantallaGestionEmpresas", "Selecciona operacion"],
            ["PantallaGestionEmpresas", "FormularioEmpresa", "Abrir formulario"],
            ["Super Administrador", "FormularioEmpresa", "Ingresa datos"],
            ["FormularioEmpresa", "ControladorGestionEmpresas", "Guardar"],
            ["ControladorGestionEmpresas", "ValidadorDatosEmpresa", "Validar NIT y email"],
            ["ValidadorDatosEmpresa", "Empresa", "Verificar existencia"],
            ["ControladorGestionEmpresas", "RegistradorEmpresa", "Crear tenant"],
            ["RegistradorEmpresa", "Empresa", "Guardar empresa"],
            ["ControladorGestionEmpresas", "RegistradorAdminEmpresa", "Crear admin"],
            ["RegistradorAdminEmpresa", "Usuario", "Guardar usuario"],
            ["RegistradorAdminEmpresa", "Rol", "Asignar rol"],
            ["ControladorGestionEmpresas", "ServicioNotificacionCredenciales", "Enviar correo"],
            ["Super Administrador", "DialogoConfirmacionEstado", "Confirmar estado"],
            ["DialogoConfirmacionEstado", "ControladorGestionEmpresas", "Aplicar cambio"],
            ["ControladorGestionEmpresas", "ActualizadorEstadoEmpresa", "Modificar estado"],
            ["ActualizadorEstadoEmpresa", "Empresa", "Actualizar BD"],
            ["ControladorGestionEmpresas", "RegistradorBitacora", "Registrar log"],
            ["RegistradorBitacora", "Bitacora", "Guardar accion"],
            ["ControladorGestionEmpresas", "PantallaGestionEmpresas", "Actualizar lista"]
        ]
    );

    // CU03
    createDiagramForCU(
        "CU03", "Gestionar planes de suscripcion",
        ["Super Administrador"],
        ["PantallaGestionPlanes", "FormularioPlan"],
        ["ControladorGestionPlanes", "ValidadorParametrosPlan", "VerificadorImpactoEmpresas", "PersistidorPlan", "AsignadorFuncionalidadesPlan", "RegistradorBitacora"],
        ["Plan", "Funcionalidad", "Empresa", "Bitacora"],
        [
            ["Super Administrador", "PantallaGestionPlanes", "Consultar planes"],
            ["PantallaGestionPlanes", "FormularioPlan", "Abrir formulario"],
            ["Super Administrador", "FormularioPlan", "Editar limites"],
            ["FormularioPlan", "ControladorGestionPlanes", "Guardar plan"],
            ["ControladorGestionPlanes", "ValidadorParametrosPlan", "Validar limites"],
            ["ControladorGestionPlanes", "VerificadorImpactoEmpresas", "Verificar empresas activas"],
            ["VerificadorImpactoEmpresas", "Empresa", "Consultar sucursales"],
            ["ControladorGestionPlanes", "PersistidorPlan", "Guardar plan"],
            ["PersistidorPlan", "Plan", "Actualizar plan"],
            ["ControladorGestionPlanes", "AsignadorFuncionalidadesPlan", "Asignar funciones"],
            ["AsignadorFuncionalidadesPlan", "Funcionalidad", "Guardar funciones"],
            ["ControladorGestionPlanes", "RegistradorBitacora", "Registrar log"],
            ["RegistradorBitacora", "Bitacora", "Guardar accion"],
            ["ControladorGestionPlanes", "PantallaGestionPlanes", "Actualizar lista"]
        ]
    );

    // CU04
    createDiagramForCU(
        "CU04", "Gestionar suscripcion de una empresa",
        ["Super Administrador", "Administrador de Empresa"],
        ["PantallaSuscripcionEmpresa", "FormularioAsignacionPlan", "PantallaMiSuscripcion"],
        ["ControladorSuscripciones", "ConsultorCatalogoPlanes", "CalculadorFechaVencimiento", "ValidadorCapacidadSucursales", "ActualizadorSuscripcion", "ExtensorVigenciaSuscripcion", "RegistradorBitacora"],
        ["Empresa", "Plan", "Suscripcion", "Sucursal", "Bitacora"],
        [
            ["Super Administrador", "PantallaSuscripcionEmpresa", "Consultar suscripcion"],
            ["PantallaSuscripcionEmpresa", "ControladorSuscripciones", "Cargar datos"],
            ["ControladorSuscripciones", "Suscripcion", "Consultar suscripcion actual"],
            ["PantallaSuscripcionEmpresa", "FormularioAsignacionPlan", "Asignar o renovar"],
            ["ControladorSuscripciones", "ConsultorCatalogoPlanes", "Listar planes"],
            ["ConsultorCatalogoPlanes", "Plan", "Obtener planes"],
            ["Super Administrador", "FormularioAsignacionPlan", "Seleccionar plan"],
            ["FormularioAsignacionPlan", "ControladorSuscripciones", "Confirmar asignacion"],
            ["ControladorSuscripciones", "CalculadorFechaVencimiento", "Calcular vencimiento"],
            ["ControladorSuscripciones", "ValidadorCapacidadSucursales", "Validar limite sucursales"],
            ["ValidadorCapacidadSucursales", "Sucursal", "Contar sucursales"],
            ["ControladorSuscripciones", "ActualizadorSuscripcion", "Crear nueva suscripcion"],
            ["ActualizadorSuscripcion", "Suscripcion", "Guardar suscripcion"],
            ["ControladorSuscripciones", "ExtensorVigenciaSuscripcion", "Extender vigencia"],
            ["ExtensorVigenciaSuscripcion", "Suscripcion", "Actualizar fecha"],
            ["ControladorSuscripciones", "RegistradorBitacora", "Registrar log"],
            ["RegistradorBitacora", "Bitacora", "Guardar accion"],
            ["Administrador de Empresa", "PantallaMiSuscripcion", "Consultar mi suscripcion"],
            ["PantallaMiSuscripcion", "ControladorSuscripciones", "Cargar modo lectura"],
            ["ControladorSuscripciones", "PantallaMiSuscripcion", "Mostrar datos"]
        ]
    );

    // CU05
    createDiagramForCU(
        "CU05", "Verificar plan y limites de la suscripcion",
        ["Sistema Backend"],
        ["InterceptorPeticionAPI"],
        ["ControladorVerificacionPlan", "ExtractorTenantToken", "VerificadorVigenciaSuscripcion", "VerificadorFuncionalidadHabilitada", "ContadorRecursosConsumidos", "ValidadorTopeRecurso", "GeneradorRespuestaAutorizacion"],
        ["TokenSesion", "Empresa", "Suscripcion", "Plan", "Funcionalidad", "Sucursal"],
        [
            ["Sistema Backend", "InterceptorPeticionAPI", "Recibe peticion"],
            ["InterceptorPeticionAPI", "ControladorVerificacionPlan", "Validar permisos"],
            ["ControladorVerificacionPlan", "ExtractorTenantToken", "Extraer token"],
            ["ExtractorTenantToken", "TokenSesion", "Leer payload"],
            ["ControladorVerificacionPlan", "VerificadorVigenciaSuscripcion", "Validar vigencia"],
            ["VerificadorVigenciaSuscripcion", "Suscripcion", "Consultar estado"],
            ["ControladorVerificacionPlan", "VerificadorFuncionalidadHabilitada", "Validar funcionalidad"],
            ["VerificadorFuncionalidadHabilitada", "Plan", "Consultar permisos del plan"],
            ["Plan", "Funcionalidad", "Verificar funcionalidad activa"],
            ["ControladorVerificacionPlan", "ContadorRecursosConsumidos", "Contar recursos usados"],
            ["ContadorRecursosConsumidos", "Sucursal", "Contar sucursales"],
            ["ControladorVerificacionPlan", "ValidadorTopeRecurso", "Comparar vs limite"],
            ["ControladorVerificacionPlan", "GeneradorRespuestaAutorizacion", "Generar respuesta"],
            ["GeneradorRespuestaAutorizacion", "InterceptorPeticionAPI", "Autorizar o rechazar"]
        ]
    );

    mainPkg.Packages.Refresh();
    pkg.Packages.Refresh();
    Session.Output("==================================================");
    Session.Output("¡Generacion de los 5 casos de uso completada con exito!");
    Session.Output("==================================================");
}

main();
