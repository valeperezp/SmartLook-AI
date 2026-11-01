/*
 * Enterprise Architect - JScript Automation
 * Diagrama de Robustez: CU05 - Verificar plan y limites de la suscripcion
 * Metodologia: ICONIX | Proyecto: SmartLook IA
 */

function main() {
	// 1. Obtener paquete seleccionado en el Project Browser
	var pkg = Repository.GetTreeSelectedPackage();
	if (!pkg) {
		Session.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);
		return;
	}

	Session.Output("Iniciando generacion de: CU05 - Verificar plan y limites de la suscripcion...");

	// 2. Crear subpaquete para organizar el Caso de Uso
	var subPkg = pkg.Packages.AddNew("CU05 - Verificar plan y limites de la suscripcion", "");
	subPkg.Update();

	// 3. Crear Diagrama de Robustez (Tipo Analysis en EA)
	var diagram = subPkg.Diagrams.AddNew("Robustez - CU05", "Analysis");
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
	elements["Sistema Backend"] = addElement("Sistema Backend", "Actor", "", 40, -50, 140, -130);

	// --- COLUMNA 2: FRONTERAS (BOUNDARIES) ---
	elements["InterceptorPeticionAPI"] = addElement("InterceptorPeticionAPI", "Boundary", "boundary", 220, -50, 380, -120);

	// --- COLUMNA 3: CONTROLES ---
	elements["ControladorVerificacionPlan"] = addElement("ControladorVerificacionPlan", "Control", "control", 460, -50, 650, -115);
	elements["ExtractorTenantToken"] = addElement("ExtractorTenantToken", "Control", "control", 460, -150, 650, -215);
	elements["VerificadorVigenciaSuscripcion"] = addElement("VerificadorVigenciaSuscripcion", "Control", "control", 460, -250, 650, -315);
	elements["VerificadorFuncionalidadHabilitada"] = addElement("VerificadorFuncionalidadHabilitada", "Control", "control", 460, -350, 650, -415);
	elements["ContadorRecursosConsumidos"] = addElement("ContadorRecursosConsumidos", "Control", "control", 460, -450, 650, -515);
	elements["ValidadorTopeRecurso"] = addElement("ValidadorTopeRecurso", "Control", "control", 460, -550, 650, -615);
	elements["GeneradorRespuestaAutorizacion"] = addElement("GeneradorRespuestaAutorizacion", "Control", "control", 460, -650, 650, -715);

	// --- COLUMNA 4: ENTIDADES ---
	elements["TokenSesion"] = addElement("TokenSesion", "Entity", "entity", 740, -50, 900, -120);
	elements["Empresa"] = addElement("Empresa", "Entity", "entity", 740, -160, 900, -230);
	elements["Suscripcion"] = addElement("Suscripcion", "Entity", "entity", 740, -270, 900, -340);
	elements["Plan"] = addElement("Plan", "Entity", "entity", 740, -380, 900, -450);
	elements["Funcionalidad"] = addElement("Funcionalidad", "Entity", "entity", 740, -490, 900, -560);
	elements["Sucursal"] = addElement("Sucursal", "Entity", "entity", 740, -600, 900, -670);

	// --- ENLACES Y COMUNICACIONES ---
	addLink(elements["Sistema Backend"], elements["InterceptorPeticionAPI"], "Recibe peticion");
	addLink(elements["InterceptorPeticionAPI"], elements["ControladorVerificacionPlan"], "Validar permisos");
	addLink(elements["ControladorVerificacionPlan"], elements["ExtractorTenantToken"], "Extraer token");
	addLink(elements["ExtractorTenantToken"], elements["TokenSesion"], "Leer payload");
	addLink(elements["ControladorVerificacionPlan"], elements["VerificadorVigenciaSuscripcion"], "Validar vigencia");
	addLink(elements["VerificadorVigenciaSuscripcion"], elements["Suscripcion"], "Consultar estado");
	addLink(elements["ControladorVerificacionPlan"], elements["VerificadorFuncionalidadHabilitada"], "Validar funcionalidad");
	addLink(elements["VerificadorFuncionalidadHabilitada"], elements["Plan"], "Consultar permisos del plan");
	addLink(elements["Plan"], elements["Funcionalidad"], "Verificar funcionalidad activa");
	addLink(elements["ControladorVerificacionPlan"], elements["ContadorRecursosConsumidos"], "Contar recursos usados");
	addLink(elements["ContadorRecursosConsumidos"], elements["Sucursal"], "Contar sucursales");
	addLink(elements["ControladorVerificacionPlan"], elements["ValidadorTopeRecurso"], "Comparar vs limite");
	addLink(elements["ControladorVerificacionPlan"], elements["GeneradorRespuestaAutorizacion"], "Generar respuesta");
	addLink(elements["GeneradorRespuestaAutorizacion"], elements["InterceptorPeticionAPI"], "Autorizar o rechazar");

	// 4. Refrescar vistas en Enterprise Architect
	diagram.DiagramObjects.Refresh();
	subPkg.Diagrams.Refresh();
	pkg.Packages.Refresh();
	Repository.ReloadDiagram(diagram.DiagramID);
	Session.Output("Diagrama CU05 generado con exito.");
}

main();