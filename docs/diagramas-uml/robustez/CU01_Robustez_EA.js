/*
 * Enterprise Architect - JScript Automation
 * Diagrama de Robustez: CU01 - Iniciar sesion en el contexto de una empresa
 * Metodologia: ICONIX | Proyecto: SmartLook IA
 */

function main() {
	// 1. Obtener paquete seleccionado en el Project Browser
	var pkg = Repository.GetTreeSelectedPackage();
	if (!pkg) {
		Session.Prompt("Por favor, selecciona un paquete en el Project Browser antes de ejecutar.", promptOK);
		return;
	}

	Session.Output("Iniciando generacion de: CU01 - Iniciar sesion en el contexto de una empresa...");

	// 2. Crear subpaquete para organizar el Caso de Uso
	var subPkg = pkg.Packages.AddNew("CU01 - Iniciar sesion en el contexto de una empresa", "");
	subPkg.Update();

	// 3. Crear Diagrama de Robustez (Tipo Analysis en EA)
	var diagram = subPkg.Diagrams.AddNew("Robustez - CU01", "Analysis");
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
	elements["Usuario"] = addElement("Usuario", "Actor", "", 40, -50, 140, -130);

	// --- COLUMNA 2: FRONTERAS (BOUNDARIES) ---
	elements["PantallaInicioSesion"] = addElement("PantallaInicioSesion", "Boundary", "boundary", 220, -50, 380, -120);
	elements["PantallaPrincipalEmpresa"] = addElement("PantallaPrincipalEmpresa", "Boundary", "boundary", 220, -160, 380, -230);
	elements["PanelAdminSaaS"] = addElement("PanelAdminSaaS", "Boundary", "boundary", 220, -270, 380, -340);

	// --- COLUMNA 3: CONTROLES ---
	elements["ControladorAutenticacion"] = addElement("ControladorAutenticacion", "Control", "control", 460, -50, 650, -115);
	elements["VerificadorCredenciales"] = addElement("VerificadorCredenciales", "Control", "control", 460, -150, 650, -215);
	elements["VerificadorEstadoEmpresa"] = addElement("VerificadorEstadoEmpresa", "Control", "control", 460, -250, 650, -315);
	elements["ValidadorVigenciaSuscripcion"] = addElement("ValidadorVigenciaSuscripcion", "Control", "control", 460, -350, 650, -415);
	elements["GeneradorTokenJWT"] = addElement("GeneradorTokenJWT", "Control", "control", 460, -450, 650, -515);
	elements["RegistradorBitacoraAcceso"] = addElement("RegistradorBitacoraAcceso", "Control", "control", 460, -550, 650, -615);

	// --- COLUMNA 4: ENTIDADES ---
	elements["Entity_Usuario"] = addElement("Usuario", "Entity", "entity", 740, -50, 900, -120);
	elements["Empresa"] = addElement("Empresa", "Entity", "entity", 740, -160, 900, -230);
	elements["Suscripcion"] = addElement("Suscripcion", "Entity", "entity", 740, -270, 900, -340);
	elements["TokenSesion"] = addElement("TokenSesion", "Entity", "entity", 740, -380, 900, -450);
	elements["Bitacora"] = addElement("Bitacora", "Entity", "entity", 740, -490, 900, -560);

	// --- ENLACES Y COMUNICACIONES ---
	addLink(elements["Usuario"], elements["PantallaInicioSesion"], "Ingresa credenciales");
	addLink(elements["PantallaInicioSesion"], elements["ControladorAutenticacion"], "Enviar login");
	addLink(elements["ControladorAutenticacion"], elements["VerificadorCredenciales"], "Verificar clave");
	addLink(elements["VerificadorCredenciales"], elements["Entity_Usuario"], "Consultar usuario");
	addLink(elements["ControladorAutenticacion"], elements["VerificadorEstadoEmpresa"], "Verificar empresa activa");
	addLink(elements["VerificadorEstadoEmpresa"], elements["Empresa"], "Consultar empresa");
	addLink(elements["ControladorAutenticacion"], elements["ValidadorVigenciaSuscripcion"], "Verificar vigencia");
	addLink(elements["ValidadorVigenciaSuscripcion"], elements["Suscripcion"], "Consultar suscripcion");
	addLink(elements["ControladorAutenticacion"], elements["GeneradorTokenJWT"], "Generar token");
	addLink(elements["GeneradorTokenJWT"], elements["TokenSesion"], "Crear sesion");
	addLink(elements["ControladorAutenticacion"], elements["RegistradorBitacoraAcceso"], "Registrar log");
	addLink(elements["RegistradorBitacoraAcceso"], elements["Bitacora"], "Guardar acceso");
	addLink(elements["ControladorAutenticacion"], elements["PantallaPrincipalEmpresa"], "Redirigir usuario");
	addLink(elements["ControladorAutenticacion"], elements["PanelAdminSaaS"], "Redirigir SuperAdmin");

	// 4. Refrescar vistas en Enterprise Architect
	diagram.DiagramObjects.Refresh();
	subPkg.Diagrams.Refresh();
	pkg.Packages.Refresh();
	Repository.ReloadDiagram(diagram.DiagramID);
	Session.Output("Diagrama CU01 generado con exito.");
}

main();