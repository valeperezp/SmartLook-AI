/*
 * Enterprise Architect - JScript Automation
 * Diagrama de Robustez: CU02 - Gestionar empresas contratantes
 * Metodologia: ICONIX | Proyecto: SmartLook IA
 */

function main() {
	// 1. Obtener paquete seleccionado en el Project Browser
	var pkg = Repository.GetTreeSelectedPackage();
	if (!pkg) {
		Session.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);
		return;
	}

	Session.Output("Iniciando generacion de: CU02 - Gestionar empresas contratantes...");

	// 2. Crear subpaquete para organizar el Caso de Uso
	var subPkg = pkg.Packages.AddNew("CU02 - Gestionar empresas contratantes", "");
	subPkg.Update();

	// 3. Crear Diagrama de Robustez (Tipo Analysis en EA)
	var diagram = subPkg.Diagrams.AddNew("Robustez - CU02", "Analysis");
	diagram.Update();

	// Diccionario de elementos para conectar posteriormente
	var elements = {};

	// Funcion auxiliar para crear elementos y posicionarlos en el diagrama
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

	// Funcion auxiliar para conectar elementos
	function addLink(sourceEl, targetEl, labelText) {
		if (!sourceEl || !targetEl) return;
		var conn = sourceEl.Connectors.AddNew(labelText, "Association");
		conn.SupplierID = targetEl.ElementID;
		conn.Direction = "Source -> Destination";
		conn.Update();
		sourceEl.Connectors.Refresh();
	}

	// --- COLUMNA 1: ACTORES ---
	elements["Super Administrador"] = addElement("Super Administrador", "Actor", "", 40, -50, 140, -130);

	// --- COLUMNA 2: FRONTERAS (BOUNDARIES) ---
	elements["PantallaGestionEmpresas"] = addElement("PantallaGestionEmpresas", "Boundary", "boundary", 220, -50, 380, -120);
	elements["FormularioEmpresa"] = addElement("FormularioEmpresa", "Boundary", "boundary", 220, -160, 380, -230);
	elements["DialogoConfirmacionEstado"] = addElement("DialogoConfirmacionEstado", "Boundary", "boundary", 220, -270, 380, -340);

	// --- COLUMNA 3: CONTROLES ---
	elements["ControladorGestionEmpresas"] = addElement("ControladorGestionEmpresas", "Control", "control", 460, -50, 650, -115);
	elements["ValidadorDatosEmpresa"] = addElement("ValidadorDatosEmpresa", "Control", "control", 460, -150, 650, -215);
	elements["RegistradorEmpresa"] = addElement("RegistradorEmpresa", "Control", "control", 460, -250, 650, -315);
	elements["RegistradorAdminEmpresa"] = addElement("RegistradorAdminEmpresa", "Control", "control", 460, -350, 650, -415);
	elements["ActualizadorEstadoEmpresa"] = addElement("ActualizadorEstadoEmpresa", "Control", "control", 460, -450, 650, -515);
	elements["ServicioNotificacionCredenciales"] = addElement("ServicioNotificacionCredenciales", "Control", "control", 460, -550, 650, -615);
	elements["RegistradorBitacora"] = addElement("RegistradorBitacora", "Control", "control", 460, -650, 650, -715);

	// --- COLUMNA 4: ENTIDADES ---
	elements["Empresa"] = addElement("Empresa", "Entity", "entity", 740, -50, 900, -120);
	elements["Usuario"] = addElement("Usuario", "Entity", "entity", 740, -160, 900, -230);
	elements["Rol"] = addElement("Rol", "Entity", "entity", 740, -270, 900, -340);
	elements["Bitacora"] = addElement("Bitacora", "Entity", "entity", 740, -380, 900, -450);

	// --- ENLACES Y COMUNICACIONES ---
	addLink(elements["Super Administrador"], elements["PantallaGestionEmpresas"], "Selecciona operacion");
	addLink(elements["PantallaGestionEmpresas"], elements["FormularioEmpresa"], "Abrir formulario");
	addLink(elements["Super Administrador"], elements["FormularioEmpresa"], "Ingresa datos");
	addLink(elements["FormularioEmpresa"], elements["ControladorGestionEmpresas"], "Guardar");
	addLink(elements["ControladorGestionEmpresas"], elements["ValidadorDatosEmpresa"], "Validar NIT y email");
	addLink(elements["ValidadorDatosEmpresa"], elements["Empresa"], "Verificar existencia");
	addLink(elements["ControladorGestionEmpresas"], elements["RegistradorEmpresa"], "Crear tenant");
	addLink(elements["RegistradorEmpresa"], elements["Empresa"], "Guardar empresa");
	addLink(elements["ControladorGestionEmpresas"], elements["RegistradorAdminEmpresa"], "Crear admin");
	addLink(elements["RegistradorAdminEmpresa"], elements["Entity_Usuario"], "Guardar usuario");
	addLink(elements["RegistradorAdminEmpresa"], elements["Rol"], "Asignar rol");
	addLink(elements["ControladorGestionEmpresas"], elements["ServicioNotificacionCredenciales"], "Enviar correo");
	addLink(elements["Super Administrador"], elements["DialogoConfirmacionEstado"], "Confirmar estado");
	addLink(elements["DialogoConfirmacionEstado"], elements["ControladorGestionEmpresas"], "Aplicar cambio");
	addLink(elements["ControladorGestionEmpresas"], elements["ActualizadorEstadoEmpresa"], "Modificar estado");
	addLink(elements["ActualizadorEstadoEmpresa"], elements["Empresa"], "Actualizar BD");
	addLink(elements["ControladorGestionEmpresas"], elements["RegistradorBitacora"], "Registrar log");
	addLink(elements["RegistradorBitacora"], elements["Bitacora"], "Guardar accion");
	addLink(elements["ControladorGestionEmpresas"], elements["PantallaGestionEmpresas"], "Actualizar lista");

	// 4. Refrescar vistas en Enterprise Architect
	diagram.DiagramObjects.Refresh();
	subPkg.Diagrams.Refresh();
	pkg.Packages.Refresh();
	Repository.ReloadDiagram(diagram.DiagramID);
	Session.Output("Diagrama CU02 generado con exito.");
}

main();