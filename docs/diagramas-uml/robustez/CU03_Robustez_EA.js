/*
 * Enterprise Architect - JScript Automation
 * Diagrama de Robustez: CU03 - Gestionar planes de suscripcion
 * Metodologia: ICONIX | Proyecto: SmartLook IA
 */

function main() {
	// 1. Obtener paquete seleccionado en el Project Browser
	var pkg = Repository.GetTreeSelectedPackage();
	if (!pkg) {
		Session.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);
		return;
	}

	Session.Output("Iniciando generacion de: CU03 - Gestionar planes de suscripcion...");

	// 2. Crear subpaquete para organizar el Caso de Uso
	var subPkg = pkg.Packages.AddNew("CU03 - Gestionar planes de suscripcion", "");
	subPkg.Update();

	// 3. Crear Diagrama de Robustez (Tipo Analysis en EA)
	var diagram = subPkg.Diagrams.AddNew("Robustez - CU03", "Analysis");
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
	elements["PantallaGestionPlanes"] = addElement("PantallaGestionPlanes", "Boundary", "boundary", 220, -50, 380, -120);
	elements["FormularioPlan"] = addElement("FormularioPlan", "Boundary", "boundary", 220, -160, 380, -230);

	// --- COLUMNA 3: CONTROLES ---
	elements["ControladorGestionPlanes"] = addElement("ControladorGestionPlanes", "Control", "control", 460, -50, 650, -115);
	elements["ValidadorParametrosPlan"] = addElement("ValidadorParametrosPlan", "Control", "control", 460, -150, 650, -215);
	elements["VerificadorImpactoEmpresas"] = addElement("VerificadorImpactoEmpresas", "Control", "control", 460, -250, 650, -315);
	elements["PersistidorPlan"] = addElement("PersistidorPlan", "Control", "control", 460, -350, 650, -415);
	elements["AsignadorFuncionalidadesPlan"] = addElement("AsignadorFuncionalidadesPlan", "Control", "control", 460, -450, 650, -515);
	elements["RegistradorBitacora"] = addElement("RegistradorBitacora", "Control", "control", 460, -550, 650, -615);

	// --- COLUMNA 4: ENTIDADES ---
	elements["Plan"] = addElement("Plan", "Entity", "entity", 740, -50, 900, -120);
	elements["Funcionalidad"] = addElement("Funcionalidad", "Entity", "entity", 740, -160, 900, -230);
	elements["Empresa"] = addElement("Empresa", "Entity", "entity", 740, -270, 900, -340);
	elements["Bitacora"] = addElement("Bitacora", "Entity", "entity", 740, -380, 900, -450);

	// --- ENLACES Y COMUNICACIONES ---
	addLink(elements["Super Administrador"], elements["PantallaGestionPlanes"], "Consultar planes");
	addLink(elements["PantallaGestionPlanes"], elements["FormularioPlan"], "Abrir formulario");
	addLink(elements["Super Administrador"], elements["FormularioPlan"], "Editar limites");
	addLink(elements["FormularioPlan"], elements["ControladorGestionPlanes"], "Guardar plan");
	addLink(elements["ControladorGestionPlanes"], elements["ValidadorParametrosPlan"], "Validar limites");
	addLink(elements["ControladorGestionPlanes"], elements["VerificadorImpactoEmpresas"], "Verificar empresas activas");
	addLink(elements["VerificadorImpactoEmpresas"], elements["Empresa"], "Consultar sucursales");
	addLink(elements["ControladorGestionPlanes"], elements["PersistidorPlan"], "Guardar plan");
	addLink(elements["PersistidorPlan"], elements["Plan"], "Actualizar plan");
	addLink(elements["ControladorGestionPlanes"], elements["AsignadorFuncionalidadesPlan"], "Asignar funciones");
	addLink(elements["AsignadorFuncionalidadesPlan"], elements["Funcionalidad"], "Guardar funciones");
	addLink(elements["ControladorGestionPlanes"], elements["RegistradorBitacora"], "Registrar log");
	addLink(elements["RegistradorBitacora"], elements["Bitacora"], "Guardar accion");
	addLink(elements["ControladorGestionPlanes"], elements["PantallaGestionPlanes"], "Actualizar lista");

	// 4. Refrescar vistas en Enterprise Architect
	diagram.DiagramObjects.Refresh();
	subPkg.Diagrams.Refresh();
	pkg.Packages.Refresh();
	Repository.ReloadDiagram(diagram.DiagramID);
	Session.Output("Diagrama CU03 generado con exito.");
}

main();