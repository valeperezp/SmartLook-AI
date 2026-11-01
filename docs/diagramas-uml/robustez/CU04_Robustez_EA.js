/*
 * Enterprise Architect - JScript Automation
 * Diagrama de Robustez: CU04 - Gestionar suscripcion de una empresa
 * Metodologia: ICONIX | Proyecto: SmartLook IA
 */

function main() {
	// 1. Obtener paquete seleccionado en el Project Browser
	var pkg = Repository.GetTreeSelectedPackage();
	if (!pkg) {
		Session.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);
		return;
	}

	Session.Output("Iniciando generacion de: CU04 - Gestionar suscripcion de una empresa...");

	// 2. Crear subpaquete para organizar el Caso de Uso
	var subPkg = pkg.Packages.AddNew("CU04 - Gestionar suscripcion de una empresa", "");
	subPkg.Update();

	// 3. Crear Diagrama de Robustez (Tipo Analysis en EA)
	var diagram = subPkg.Diagrams.AddNew("Robustez - CU04", "Analysis");
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
	elements["Administrador de Empresa"] = addElement("Administrador de Empresa", "Actor", "", 40, -170, 140, -250);

	// --- COLUMNA 2: FRONTERAS (BOUNDARIES) ---
	elements["PantallaSuscripcionEmpresa"] = addElement("PantallaSuscripcionEmpresa", "Boundary", "boundary", 220, -50, 380, -120);
	elements["FormularioAsignacionPlan"] = addElement("FormularioAsignacionPlan", "Boundary", "boundary", 220, -160, 380, -230);
	elements["PantallaMiSuscripcion"] = addElement("PantallaMiSuscripcion", "Boundary", "boundary", 220, -270, 380, -340);

	// --- COLUMNA 3: CONTROLES ---
	elements["ControladorSuscripciones"] = addElement("ControladorSuscripciones", "Control", "control", 460, -50, 650, -115);
	elements["ConsultorCatalogoPlanes"] = addElement("ConsultorCatalogoPlanes", "Control", "control", 460, -150, 650, -215);
	elements["CalculadorFechaVencimiento"] = addElement("CalculadorFechaVencimiento", "Control", "control", 460, -250, 650, -315);
	elements["ValidadorCapacidadSucursales"] = addElement("ValidadorCapacidadSucursales", "Control", "control", 460, -350, 650, -415);
	elements["ActualizadorSuscripcion"] = addElement("ActualizadorSuscripcion", "Control", "control", 460, -450, 650, -515);
	elements["ExtensorVigenciaSuscripcion"] = addElement("ExtensorVigenciaSuscripcion", "Control", "control", 460, -550, 650, -615);
	elements["RegistradorBitacora"] = addElement("RegistradorBitacora", "Control", "control", 460, -650, 650, -715);

	// --- COLUMNA 4: ENTIDADES ---
	elements["Empresa"] = addElement("Empresa", "Entity", "entity", 740, -50, 900, -120);
	elements["Plan"] = addElement("Plan", "Entity", "entity", 740, -160, 900, -230);
	elements["Suscripcion"] = addElement("Suscripcion", "Entity", "entity", 740, -270, 900, -340);
	elements["Sucursal"] = addElement("Sucursal", "Entity", "entity", 740, -380, 900, -450);
	elements["Bitacora"] = addElement("Bitacora", "Entity", "entity", 740, -490, 900, -560);

	// --- ENLACES Y COMUNICACIONES ---
	addLink(elements["Super Administrador"], elements["PantallaSuscripcionEmpresa"], "Consultar suscripcion");
	addLink(elements["PantallaSuscripcionEmpresa"], elements["ControladorSuscripciones"], "Cargar datos");
	addLink(elements["ControladorSuscripciones"], elements["Suscripcion"], "Consultar suscripcion actual");
	addLink(elements["PantallaSuscripcionEmpresa"], elements["FormularioAsignacionPlan"], "Asignar o renovar");
	addLink(elements["ControladorSuscripciones"], elements["ConsultorCatalogoPlanes"], "Listar planes");
	addLink(elements["ConsultorCatalogoPlanes"], elements["Plan"], "Obtener planes");
	addLink(elements["Super Administrador"], elements["FormularioAsignacionPlan"], "Seleccionar plan");
	addLink(elements["FormularioAsignacionPlan"], elements["ControladorSuscripciones"], "Confirmar asignacion");
	addLink(elements["ControladorSuscripciones"], elements["CalculadorFechaVencimiento"], "Calcular vencimiento");
	addLink(elements["ControladorSuscripciones"], elements["ValidadorCapacidadSucursales"], "Validar limite sucursales");
	addLink(elements["ValidadorCapacidadSucursales"], elements["Sucursal"], "Contar sucursales");
	addLink(elements["ControladorSuscripciones"], elements["ActualizadorSuscripcion"], "Crear nueva suscripcion");
	addLink(elements["ActualizadorSuscripcion"], elements["Suscripcion"], "Guardar suscripcion");
	addLink(elements["ControladorSuscripciones"], elements["ExtensorVigenciaSuscripcion"], "Extender vigencia");
	addLink(elements["ExtensorVigenciaSuscripcion"], elements["Suscripcion"], "Actualizar fecha");
	addLink(elements["ControladorSuscripciones"], elements["RegistradorBitacora"], "Registrar log");
	addLink(elements["RegistradorBitacora"], elements["Bitacora"], "Guardar accion");
	addLink(elements["Administrador de Empresa"], elements["PantallaMiSuscripcion"], "Consultar mi suscripcion");
	addLink(elements["PantallaMiSuscripcion"], elements["ControladorSuscripciones"], "Cargar modo lectura");
	addLink(elements["ControladorSuscripciones"], elements["PantallaMiSuscripcion"], "Mostrar datos");

	// 4. Refrescar vistas en Enterprise Architect
	diagram.DiagramObjects.Refresh();
	subPkg.Diagrams.Refresh();
	pkg.Packages.Refresh();
	Repository.ReloadDiagram(diagram.DiagramID);
	Session.Output("Diagrama CU04 generado con exito.");
}

main();