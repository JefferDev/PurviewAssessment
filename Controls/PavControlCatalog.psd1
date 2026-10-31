#
# Catálogo de controles del assessment de Microsoft Purview.
#
# Marco propio de evaluación. Cada control declara qué debe existir en un
# despliegue maduro, por qué importa y cómo se verifica. Los enunciados,
# identificadores y criterios son propios del módulo.
#
# Esquema de identificador: PAV-<DOMINIO>-<NN>
#   MIP  Etiquetas de confidencialidad e Information Protection
#   DLP  Prevención de pérdida de datos
#   RM   Gestión de registros
#   DLM  Ciclo de vida de los datos (retención)
#   CC   Cumplimiento de comunicaciones
#   IRM  Gestión de riesgo interno
#   AUD  Auditoría
#   EDS  Descubrimiento electrónico
#   AI   Gobierno de inteligencia artificial
#
# Campos por control:
#   Id             Identificador estable. No se reutiliza si un control se retira.
#   Domain         Código de dominio.
#   Title          Enunciado en positivo: qué debe existir.
#   Rationale      Por qué el control importa desde la perspectiva de gobierno.
#   BusinessImpact Consecuencia concreta si el control no está implementado.
#   Severity       Severidad base: Alta | Media | Baja. El evaluador puede elevarla
#                  o reducirla según el contexto del tenant.
#   Type           Technical  : se verifica con la configuración del tenant.
#                  Process    : requiere confirmación con el cliente.
#                  Hybrid     : configuración verificable + práctica declarada.
#   Evaluator      Función privada que emite el veredicto. Vacío en controles Process.
#   Workload       Carga de trabajo cuyos datos consume el evaluador.
#   Frameworks     Referencias normativas de apoyo.
#   License        Nivel de licenciamiento habitual del control.
#
@{
    CatalogVersion = '1.0'
    Updated        = '2026-08-15'

    Domains = @(
        @{ Code = 'MIP'; Name = 'Etiquetas MIP';            Order = 1 }
        @{ Code = 'DLP'; Name = 'Prevención de pérdida de datos'; Order = 2 }
        @{ Code = 'RM';  Name = 'Gestión de registros';     Order = 3 }
        @{ Code = 'DLM'; Name = 'Ciclo de vida de datos';   Order = 4 }
        @{ Code = 'CC';  Name = 'Cumplimiento de comunicaciones'; Order = 5 }
        @{ Code = 'IRM'; Name = 'Riesgo interno';           Order = 6 }
        @{ Code = 'AUD'; Name = 'Auditoría';                Order = 7 }
        @{ Code = 'EDS'; Name = 'Descubrimiento electrónico'; Order = 8 }
        @{ Code = 'AI';  Name = 'Gobierno de IA';           Order = 9 }
    )

    Controls = @(

        @{
            Id     = 'PAV-MIP-01'
            Domain = 'MIP'
            Title  = 'La taxonomía de etiquetas está organizada de forma jerárquica'
            Rationale = 'Una jerarquía de etiquetas principales con subetiquetas reduce el número de opciones que el usuario ve en primer nivel y permite diferenciar variantes sin multiplicar la taxonomía visible.'
            BusinessImpact = 'Una lista plana y extensa de etiquetas incrementa el error de clasificación y el abandono del etiquetado por parte del usuario.'
            Severity = 'Baja'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip01'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12')
            License = 'E3'
        }

        @{
            Id     = 'PAV-MIP-02'
            Domain = 'MIP'
            Title  = 'Las etiquetas de mayor confidencialidad aplican cifrado'
            Rationale = 'El cifrado vinculado a la etiqueta mantiene la protección cuando el contenido sale del perímetro de la organización, que es donde los controles de ubicación dejan de aplicar.'
            BusinessImpact = 'El contenido clasificado como confidencial circula sin protección efectiva una vez compartido fuera de la organización.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip02'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.8.24', 'NIST SP 800-53 SC-28')
            License = 'E3'
        }

        @{
            Id     = 'PAV-MIP-03'
            Domain = 'MIP'
            Title  = 'Las etiquetas aplican marcado visual del contenido'
            Rationale = 'Encabezados, pies y marcas de agua comunican la clasificación al destinatario incluso cuando el documento se imprime, se fotografía o se abre fuera de la plataforma.'
            BusinessImpact = 'El receptor del documento no percibe su nivel de confidencialidad y lo trata como información ordinaria.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip03'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.13')
            License = 'E3'
        }

        @{
            Id     = 'PAV-MIP-04'
            Domain = 'MIP'
            Title  = 'Existe etiqueta predeterminada para documentos y para correo'
            Rationale = 'La etiqueta predeterminada garantiza una clasificación mínima en todo el contenido nuevo sin depender de que el usuario elija.'
            BusinessImpact = 'El contenido creado sin intervención del usuario queda sin clasificar y fuera del alcance de las directivas que dependen de la etiqueta.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip04'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12')
            License = 'E3'
        }

        @{
            Id     = 'PAV-MIP-05'
            Domain = 'MIP'
            Title  = 'El etiquetado obligatorio está activo en las directivas de publicación'
            Rationale = 'Sin obligatoriedad, la clasificación es voluntaria y su cobertura depende de la disciplina individual, no de una regla de la organización.'
            BusinessImpact = 'Cualquier usuario puede crear y compartir contenido sensible sin clasificación alguna.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip05'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12', 'NIST SP 800-53 AC-16')
            License = 'E3'
        }

        @{
            Id     = 'PAV-MIP-06'
            Domain = 'MIP'
            Title  = 'Se exige justificación al reducir el nivel de una etiqueta'
            Rationale = 'La justificación obligatoria deja rastro auditable de las reclasificaciones a la baja, que son el camino habitual para eludir los controles asociados a la etiqueta.'
            BusinessImpact = 'Un usuario puede degradar la clasificación de un documento sensible sin dejar evidencia ni motivo.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip06'
            Workload = 'MIP'
            Frameworks = @('NIST SP 800-53 AU-2')
            License = 'E3'
        }

        @{
            Id     = 'PAV-MIP-07'
            Domain = 'MIP'
            Title  = 'Existen directivas de etiquetado automático desplegadas'
            Rationale = 'El etiquetado del lado del servicio alcanza el contenido histórico y el que se crea sin intervención del usuario, que la clasificación manual nunca cubre.'
            BusinessImpact = 'La clasificación se limita al contenido que los usuarios etiquetan de forma consciente; el repositorio histórico permanece sin clasificar.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip07'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12')
            License = 'E5'
        }

        @{
            Id     = 'PAV-MIP-08'
            Domain = 'MIP'
            Title  = 'El etiquetado automático opera en modo productivo y no en simulación'
            Rationale = 'Una directiva en simulación evalúa el contenido y reporta coincidencias, pero no aplica ninguna etiqueta. Su existencia no equivale a protección.'
            BusinessImpact = 'La organización supone que el contenido se clasifica automáticamente cuando en realidad ninguna etiqueta se está aplicando.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip08'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12')
            License = 'E5'
        }

        @{
            Id     = 'PAV-MIP-09'
            Domain = 'MIP'
            Title  = 'El etiquetado automático utiliza los tipos de información sensible propios de la organización'
            Rationale = 'Los identificadores regulados de cada país y los formatos internos de negocio no están cubiertos por los patrones integrados. Si ya existen como SIT personalizados, deben alimentar también la clasificación automática.'
            BusinessImpact = 'Los datos característicos de la organización no se clasifican automáticamente aunque sus identificadores ya estén construidos y en uso en otras directivas.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip09'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12')
            License = 'E5'
        }

        @{
            Id     = 'PAV-MIP-10'
            Domain = 'MIP'
            Title  = 'La taxonomía se ha revisado dentro de un periodo razonable'
            Rationale = 'Una taxonomía que no se revisa deja de reflejar la estructura de la organización y los requisitos regulatorios vigentes, y acumula etiquetas que nadie usa.'
            BusinessImpact = 'La clasificación disponible no corresponde a la realidad del negocio, lo que induce a los usuarios a elegir etiquetas inadecuadas.'
            Severity = 'Baja'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlMip10'
            Workload = 'MIP'
            Frameworks = @('ISO/IEC 27001 A.5.12')
            License = 'E3'
        }

        # ── Prevención de pérdida de datos ────────────────────────────────────

        @{
            Id     = 'PAV-DLP-01'
            Domain = 'DLP'
            Title  = 'Las directivas emplean tipos de información sensible propios de la organización'
            Rationale = 'Los identificadores regulados de cada país y los formatos internos de negocio no están cubiertos por los patrones integrados del servicio.'
            BusinessImpact = 'Los datos característicos de la organización circulan sin detección porque ninguna regla sabe reconocerlos.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp01'
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.8.12', 'NIST SP 800-53 SI-4')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-02'
            Domain = 'DLP'
            Title  = 'Existe cobertura para datos de identificación personal'
            Rationale = 'Los identificadores personales son el dato regulado más frecuente y el de mayor exposición en fugas.'
            BusinessImpact = 'La salida de datos personales no se detecta ni se bloquea, con la consiguiente exposición ante la autoridad de protección de datos.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp02'
            Workload = 'DLP'
            Frameworks = @('GDPR Art. 32', 'ISO/IEC 27001 A.8.12')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-03'
            Domain = 'DLP'
            Title  = 'Existe cobertura para información financiera y de medios de pago'
            Rationale = 'Los datos de tarjetas y cuentas bancarias tienen requisitos contractuales de protección propios, independientes de la normativa de datos personales.'
            BusinessImpact = 'La exposición de datos de pago compromete el cumplimiento contractual con las marcas de tarjetas y habilita el fraude.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp03'
            Workload = 'DLP'
            Frameworks = @('PCI DSS 3.4', 'ISO/IEC 27001 A.8.12')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-04'
            Domain = 'DLP'
            Title  = 'Existe cobertura para información de salud, cuando el negocio la maneja'
            Rationale = 'Los datos de salud son categoría especial en la mayoría de marcos regulatorios y exigen protección reforzada.'
            BusinessImpact = 'Si la organización trata datos de salud sin detección específica, incumple la protección reforzada que exige la normativa para categorías especiales.'
            Severity = 'Media'
            Type = 'Hybrid'
            Evaluator = 'Test-PavCtrlDlp04'
            Workload = 'DLP'
            Frameworks = @('GDPR Art. 9', 'HIPAA 164.312')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-05'
            Domain = 'DLP'
            Title  = 'Las directivas operan en modo de aplicación y no en prueba'
            Rationale = 'Una directiva en modo de prueba evalúa y reporta, pero no impide ninguna acción del usuario.'
            BusinessImpact = 'La organización supone protección activa mientras las directivas solo observan, sin bloquear ninguna fuga.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp05'
            Workload = 'DLP'
            Frameworks = @('NIST SP 800-53 SI-4')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-06'
            Domain = 'DLP'
            Title  = 'La cobertura alcanza las cargas de trabajo donde circula la información'
            Rationale = 'Una fuga se produce por el canal desatendido. La cobertura parcial desplaza el riesgo en lugar de reducirlo.'
            BusinessImpact = 'Los canales sin directiva se convierten en la vía natural de salida de información sensible.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp06'
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.8.12')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-07'
            Domain = 'DLP'
            Title  = 'Las reglas aplican acciones de bloqueo o restricción de acceso'
            Rationale = 'Detectar sin actuar produce evidencia del incidente, no prevención.'
            BusinessImpact = 'La información sensible sale de la organización aunque la directiva la haya detectado correctamente.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp07'
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.8.12', 'NIST SP 800-53 AC-4')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-08'
            Domain = 'DLP'
            Title  = 'Las reglas notifican al usuario mediante sugerencias de directiva'
            Rationale = 'La notificación en el momento de la acción corrige el comportamiento y reduce la reincidencia mejor que cualquier campaña de concienciación posterior.'
            BusinessImpact = 'El usuario desconoce que su acción vulnera una política y repite el intento por otros canales.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp08'
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.6.3')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-09'
            Domain = 'DLP'
            Title  = 'Las reglas generan alertas e informes de incidente'
            Rationale = 'Sin alerta no hay respuesta: el evento queda registrado pero nadie lo atiende.'
            BusinessImpact = 'Los intentos de fuga se acumulan sin que ninguna persona los revise ni escale.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp09'
            Workload = 'DLP'
            Frameworks = @('NIST SP 800-53 IR-5')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-10'
            Domain = 'DLP'
            Title  = 'El inventario está depurado de directivas inertes u obsoletas'
            Rationale = 'Las directivas deshabilitadas o sin mantenimiento duplican lógica de detección, distorsionan la lectura de cobertura y dificultan el gobierno del conjunto vigente.'
            BusinessImpact = 'La organización sobreestima su cobertura real al contar directivas que no protegen nada.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlDlp10'
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.5.1')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-11'
            Domain = 'DLP'
            Title  = 'Existe una cadencia formal de revisión de alertas e informes'
            Rationale = 'La inversión en detección solo rinde si alguien revisa los resultados con una periodicidad definida y ajusta las reglas en consecuencia.'
            BusinessImpact = 'La detección opera sin ciclo de mejora: los falsos positivos no se corrigen y las fugas reales pueden pasar inadvertidas.'
            Severity = 'Media'
            Type = 'Process'
            Evaluator = ''
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.5.36', 'NIST SP 800-53 IR-5')
            License = 'E3'
        }

        @{
            Id     = 'PAV-DLP-12'
            Domain = 'DLP'
            Title  = 'Las exclusiones de las directivas se revisan periódicamente'
            Rationale = 'Toda exclusión es un agujero deliberado en la detección. Sin revisión, las excepciones temporales se vuelven permanentes y nadie recuerda su motivo.'
            BusinessImpact = 'Las exclusiones acumuladas se convierten en vías de fuga silenciosas que la organización desconoce.'
            Severity = 'Media'
            Type = 'Process'
            Evaluator = ''
            Workload = 'DLP'
            Frameworks = @('ISO/IEC 27001 A.5.36')
            License = 'E3'
        }

        # ── Gestión de registros ──────────────────────────────────────────────

        @{
            Id     = 'PAV-RM-01'
            Domain = 'RM'
            Title  = 'Existen etiquetas que declaran el contenido como registro'
            Rationale = 'Una etiqueta de retención conserva el contenido; solo la declaración como registro lo hace inmutable e impide su alteración o eliminación por parte del usuario.'
            BusinessImpact = 'La organización conserva información pero no puede sostener ante un regulador que sea inalterable desde su declaración.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm01'
            Workload = 'RM'
            Frameworks = @('ISO 15489', 'ISO/IEC 27001 A.5.33')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-02'
            Domain = 'RM'
            Title  = 'Los registros regulados se distinguen de los registros ordinarios'
            Rationale = 'El registro regulado impide incluso al administrador retirar la etiqueta o acortar el periodo, que es lo que exige la normativa sectorial cuando la conservación es obligatoria.'
            BusinessImpact = 'La información sujeta a obligación legal de conservación puede ser modificada o liberada por un administrador.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm02'
            Workload = 'RM'
            Frameworks = @('ISO 15489')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-03'
            Domain = 'RM'
            Title  = 'El plan de archivos está definido con sus descriptores'
            Rationale = 'Los descriptores de departamento, categoría, autoridad y citación son lo que permite explicar a un auditor por qué un documento se conserva el tiempo que se conserva.'
            BusinessImpact = 'La organización no puede justificar la política de conservación aplicada a cada tipo documental.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm03'
            Workload = 'RM'
            Frameworks = @('ISO 15489', 'ISO/IEC 27001 A.5.33')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-04'
            Domain = 'RM'
            Title  = 'Las citaciones del plan de archivos referencian la norma que las sustenta'
            Rationale = 'Una citación sin referencia normativa ni jurisdicción no es trazable: nombra una obligación sin permitir verificarla.'
            BusinessImpact = 'Los periodos de conservación no pueden vincularse a la disposición legal que los origina.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm04'
            Workload = 'RM'
            Frameworks = @('ISO 15489')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-05'
            Domain = 'RM'
            Title  = 'Las etiquetas de registro tienen plan de archivos asignado'
            Rationale = 'El catálogo de descriptores solo aporta valor si las etiquetas lo referencian: de otro modo el plan existe en el papel pero no en el contenido.'
            BusinessImpact = 'Los registros declarados no pueden clasificarse ni auditarse por área, categoría ni fundamento normativo.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm05'
            Workload = 'RM'
            Frameworks = @('ISO 15489')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-06'
            Domain = 'RM'
            Title  = 'Existe retención basada en eventos de negocio'
            Rationale = 'Numerosos plazos legales no se cuentan desde la creación del documento, sino desde un hecho posterior: la baja del empleado, el cierre del contrato o el fin de la relación comercial.'
            BusinessImpact = 'Los plazos se computan desde una fecha incorrecta, lo que produce destrucción anticipada o conservación excesiva.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm06'
            Workload = 'RM'
            Frameworks = @('ISO 15489')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-07'
            Domain = 'RM'
            Title  = 'Los tipos de evento están asociados a etiquetas de retención'
            Rationale = 'Un tipo de evento sin etiquetas asociadas no dispara el cómputo de ningún periodo: es una definición inerte.'
            BusinessImpact = 'El evento se registra en el sistema pero no altera la conservación de ningún contenido.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm07'
            Workload = 'RM'
            Frameworks = @('ISO 15489')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-08'
            Domain = 'RM'
            Title  = 'La eliminación de registros pasa por revisión de disposición'
            Rationale = 'La revisión previa a la destrucción es lo que convierte la eliminación en un acto deliberado y documentado, en lugar de un vencimiento automático.'
            BusinessImpact = 'El contenido se destruye sin que nadie valide que procede hacerlo, sin posibilidad de detener el proceso.'
            Severity = 'Alta'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm08'
            Workload = 'RM'
            Frameworks = @('ISO 15489', 'NIST SP 800-53 AU-11')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-09'
            Domain = 'RM'
            Title  = 'Las etiquetas de registro se aplican de forma automática'
            Rationale = 'Si la declaración de registro depende de una acción manual del usuario, la cobertura real será una fracción del contenido que debería estar declarado.'
            BusinessImpact = 'La conservación obligatoria se aplica de forma desigual, según la diligencia de cada usuario.'
            Severity = 'Media'
            Type = 'Technical'
            Evaluator = 'Test-PavCtrlRm09'
            Workload = 'RM'
            Frameworks = @('ISO 15489')
            License = 'E5'
        }

        @{
            Id     = 'PAV-RM-10'
            Domain = 'RM'
            Title  = 'Existe evidencia documentada de la destrucción de registros'
            Rationale = 'La defensa ante un auditor exige demostrar no solo qué se conserva, sino que lo destruido se destruyó conforme a la política y con constancia de ello.'
            BusinessImpact = 'La organización no puede acreditar la eliminación lícita de la información que ya no conserva.'
            Severity = 'Alta'
            Type = 'Process'
            Evaluator = ''
            Workload = 'RM'
            Frameworks = @('ISO 15489', 'NIST SP 800-53 AU-11')
            License = 'E5'
        }

        # ── Ciclo de vida de los datos ────────────────────────────────────────

        @{ Id='PAV-DLM-01'; Domain='DLM'
           Title='Existen directivas de retención desplegadas'
           Rationale='Sin directivas de retención, la conservación y la eliminación dependen de la acción individual de cada usuario.'
           BusinessImpact='La información se acumula de forma indefinida y sin criterio, con el consiguiente coste y exposición.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlDlm01'; Workload='DLM'
           Frameworks=@('ISO/IEC 27001 A.5.33'); License='E3' }

        @{ Id='PAV-DLM-02'; Domain='DLM'
           Title='La retención alcanza las cargas de trabajo donde reside la información'
           Rationale='Una carga sin directiva conserva su contenido fuera de toda política, y suele ser donde más volumen se acumula.'
           BusinessImpact='Existen repositorios completos sin criterio de conservación ni de eliminación.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlDlm02'; Workload='DLM'
           Frameworks=@('ISO/IEC 27001 A.5.33'); License='E3' }

        @{ Id='PAV-DLM-03'; Domain='DLM'
           Title='Existen etiquetas de retención disponibles para el contenido'
           Rationale='Las etiquetas permiten aplicar periodos distintos por tipo documental, que es lo que exige cualquier marco de conservación.'
           BusinessImpact='Toda la información recibe el mismo tratamiento con independencia de su valor o de su obligación legal.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlDlm03'; Workload='DLM'
           Frameworks=@('ISO/IEC 27001 A.5.33'); License='E3' }

        @{ Id='PAV-DLM-04'; Domain='DLM'
           Title='Existen reglas que eliminan el contenido al vencer su periodo'
           Rationale='Una política que solo conserva produce acumulación indefinida: la eliminación al vencimiento es la mitad del ciclo de vida.'
           BusinessImpact='La organización conserva información más allá de su necesidad legal o de negocio, ampliando la superficie expuesta ante una brecha.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlDlm04'; Workload='DLM'
           Frameworks=@('GDPR Art. 5.1.e', 'ISO/IEC 27001 A.5.33'); License='E3' }

        @{ Id='PAV-DLM-05'; Domain='DLM'
           Title='Las directivas operan en modo de aplicación y no en simulación'
           Rationale='Una directiva en simulación evalúa el alcance pero no conserva ni elimina nada.'
           BusinessImpact='La organización supone que la retención está activa cuando ningún contenido se está gobernando.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlDlm05'; Workload='DLM'
           Frameworks=@('ISO/IEC 27001 A.5.33'); License='E3' }

        @{ Id='PAV-DLM-06'; Domain='DLM'
           Title='El alcance se mantiene mediante ámbitos adaptativos'
           Rationale='El ámbito estático exige mantenimiento manual cada vez que cambia la organización; el adaptativo se recalcula solo.'
           BusinessImpact='El alcance de la retención se desactualiza en silencio conforme cambian áreas, ubicaciones y personas.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlDlm06'; Workload='DLM'
           Frameworks=@('ISO/IEC 27001 A.5.33'); License='E5' }

        @{ Id='PAV-DLM-07'; Domain='DLM'
           Title='Las directivas críticas cuentan con bloqueo de preservación'
           Rationale='Sin bloqueo de preservación, un administrador puede modificar o eliminar la directiva, lo que anula su valor probatorio.'
           BusinessImpact='La política de conservación no es defendible ante un regulador porque pudo alterarse en cualquier momento.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlDlm07'; Workload='DLM'
           Frameworks=@('ISO 15489', 'NIST SP 800-53 AU-9'); License='E3' }

        @{ Id='PAV-DLM-08'; Domain='DLM'
           Title='Los periodos se computan desde el hecho que exige la norma'
           Rationale='Muchos plazos legales no cuentan desde la creación del documento sino desde su última modificación, su etiquetado o un evento de negocio.'
           BusinessImpact='El contenido se elimina antes de tiempo o se conserva de más porque el cómputo parte de una fecha que no es la exigida.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlDlm08'; Workload='DLM'
           Frameworks=@('ISO 15489'); License='E3' }

        @{ Id='PAV-DLM-09'; Domain='DLM'
           Title='La configuración de retención se ha revisado recientemente'
           Rationale='Los periodos y el alcance deben seguir el ritmo de los cambios normativos y organizativos.'
           BusinessImpact='La política vigente refleja requisitos que pueden haber cambiado desde su definición.'
           Severity='Baja'; Type='Technical'; Evaluator='Test-PavCtrlDlm09'; Workload='DLM'
           Frameworks=@('ISO/IEC 27001 A.5.36'); License='E3' }

        @{ Id='PAV-DLM-10'; Domain='DLM'
           Title='Los periodos de retención están alineados con los requisitos legales documentados'
           Rationale='El periodo configurado debe poder justificarse frente a una norma concreta, no responder a una estimación.'
           BusinessImpact='La organización no puede sustentar por qué conserva cada tipo documental el tiempo que lo conserva.'
           Severity='Alta'; Type='Process'; Evaluator=''; Workload='DLM'
           Frameworks=@('ISO 15489', 'GDPR Art. 5.1.e'); License='E3' }

        # ── Cumplimiento de comunicaciones ────────────────────────────────────

        @{ Id='PAV-CC-01'; Domain='CC'
           Title='Existen directivas de cumplimiento de comunicaciones activas'
           Rationale='Sin directivas, ninguna comunicación se analiza en busca de conducta indebida, fuga de información o incumplimiento regulatorio.'
           BusinessImpact='La organización no detecta comunicaciones inapropiadas ni puede acreditar supervisión ante un regulador que la exija.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlCc01'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-02'; Domain='CC'
           Title='Las directivas están aprovisionadas y operativas'
           Rationale='Una directiva creada pero en aprovisionamiento no analiza contenido: existe en la consola sin producir efecto.'
           BusinessImpact='Se supone supervisión activa mientras ninguna comunicación se está evaluando.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlCc02'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-03'; Domain='CC'
           Title='La supervisión alcanza los canales de comunicación relevantes'
           Rationale='El canal no supervisado se convierte en la vía natural para la conducta que se pretende detectar.'
           BusinessImpact='Las comunicaciones de mayor volumen o riesgo quedan fuera de todo análisis.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlCc03'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-04'; Domain='CC'
           Title='Las directivas tienen revisores asignados'
           Rationale='Sin revisor nombrado, los elementos marcados se acumulan sin que nadie los triye ni resuelva.'
           BusinessImpact='La detección no deriva en ninguna acción y el expediente de supervisión queda vacío.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlCc04'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-05'; Domain='CC'
           Title='La detección emplea clasificadores entrenables'
           Rationale='Las categorías de conducta (acoso, amenaza, lenguaje inapropiado) no se detectan con listas de palabras: requieren clasificadores entrenados.'
           BusinessImpact='Solo se detectan coincidencias literales, y la conducta expresada con matices pasa inadvertida.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlCc05'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-06'; Domain='CC'
           Title='El porcentaje de muestreo permite una supervisión representativa'
           Rationale='Un muestreo bajo reduce el volumen de revisión pero también la probabilidad de detectar el incidente aislado.'
           BusinessImpact='La conducta indebida puede quedar fuera de la muestra revisada.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlCc06'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-07'; Domain='CC'
           Title='El reconocimiento óptico analiza el contenido de las imágenes'
           Rationale='Buena parte del contenido sensible circula como captura de pantalla o fotografía, invisible para el análisis de texto.'
           BusinessImpact='La información compartida como imagen elude por completo la supervisión.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlCc07'; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        @{ Id='PAV-CC-08'; Domain='CC'
           Title='Existe un proceso documentado de revisión y resolución'
           Rationale='La supervisión exige un circuito definido de triaje, escalamiento y cierre, con responsables y plazos.'
           BusinessImpact='Los elementos marcados se resuelven de forma inconsistente y sin trazabilidad ante una auditoría.'
           Severity='Media'; Type='Process'; Evaluator=''; Workload='CC'
           Frameworks=@('ISO/IEC 27001 A.5.34'); License='E5' }

        # ── Riesgo interno ────────────────────────────────────────────────────

        @{ Id='PAV-IRM-01'; Domain='IRM'
           Title='Existen directivas de riesgo interno habilitadas'
           Rationale='La detección de riesgo interno cubre el vector que los controles perimetrales no alcanzan: el usuario legítimo.'
           BusinessImpact='La exfiltración por parte de personal con acceso autorizado no se detecta.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlIrm01'; Workload='IRM'
           Frameworks=@('ISO/IEC 27001 A.6.1', 'NIST SP 800-53 PM-12'); License='E5' }

        @{ Id='PAV-IRM-02'; Domain='IRM'
           Title='Las directivas se encuentran en estado saludable'
           Rationale='Una directiva con problemas de configuración o de conectores no genera alertas aunque figure habilitada.'
           BusinessImpact='La cobertura declarada no se corresponde con la detección real.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlIrm02'; Workload='IRM'
           Frameworks=@('NIST SP 800-53 PM-12'); License='E5' }

        @{ Id='PAV-IRM-03'; Domain='IRM'
           Title='La cobertura incluye la fuga de información y la salida de personal'
           Rationale='La exfiltración previa a una baja es el escenario más frecuente y el que más valor concentra.'
           BusinessImpact='La sustracción de información por parte de quien abandona la organización pasa inadvertida.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlIrm03'; Workload='IRM'
           Frameworks=@('NIST SP 800-53 PS-4'); License='E5' }

        @{ Id='PAV-IRM-04'; Domain='IRM'
           Title='Las directivas consumen indicadores de actividad suficientes'
           Rationale='La puntuación de riesgo depende de la variedad de señales: sin indicadores activos no hay evaluación de comportamiento.'
           BusinessImpact='Las alertas se basan en muy pocas señales, con exceso de falsos positivos o de omisiones.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlIrm04'; Workload='IRM'
           Frameworks=@('NIST SP 800-53 PM-12'); License='E5' }

        @{ Id='PAV-IRM-05'; Domain='IRM'
           Title='Las ventanas de detección cubren un periodo suficiente'
           Rationale='Las ventanas de actividad en ámbito e histórica determinan cuánto contexto se evalúa alrededor de un hecho.'
           BusinessImpact='Una ventana corta impide correlacionar la actividad previa que da sentido a la alerta.'
           Severity='Baja'; Type='Technical'; Evaluator='Test-PavCtrlIrm05'; Workload='IRM'
           Frameworks=@('NIST SP 800-53 PM-12'); License='E5' }

        @{ Id='PAV-IRM-06'; Domain='IRM'
           Title='La investigación protege la identidad del empleado hasta que procede revelarla'
           Rationale='La seudonimización permite investigar sin exponer identidades, requisito habitual de privacidad laboral y de representación de los trabajadores.'
           BusinessImpact='Las identidades quedan expuestas durante el análisis, con riesgo de privacidad y de conflicto laboral.'
           Severity='Media'; Type='Process'; Evaluator=''; Workload='IRM'
           Frameworks=@('GDPR Art. 5.1.c'); License='E5' }

        @{ Id='PAV-IRM-07'; Domain='IRM'
           Title='Existe un flujo documentado de triaje e investigación de alertas'
           Rationale='Sin circuito definido, las alertas se acumulan y la respuesta depende de la iniciativa individual.'
           BusinessImpact='El tiempo de respuesta ante un incidente interno es impredecible y no auditable.'
           Severity='Media'; Type='Process'; Evaluator=''; Workload='IRM'
           Frameworks=@('NIST SP 800-53 IR-4'); License='E5' }

        # ── Auditoría ─────────────────────────────────────────────────────────

        @{ Id='PAV-AUD-01'; Domain='AUD'
           Title='El registro de auditoría unificada está habilitado'
           Rationale='Es la fuente de evidencia de toda actividad de usuarios y administradores; sin ella no hay investigación forense posible.'
           BusinessImpact='La organización no puede reconstruir qué ocurrió ante un incidente ni acreditar actividad ante un regulador.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlAud01'; Workload='AUDIT'
           Frameworks=@('ISO/IEC 27001 A.8.15', 'NIST SP 800-53 AU-2'); License='E3' }

        @{ Id='PAV-AUD-02'; Domain='AUD'
           Title='La auditoría de buzones está activa en la organización'
           Rationale='Las acciones sobre buzones son el rastro principal en investigaciones de acceso indebido al correo.'
           BusinessImpact='No queda constancia de quién accedió, movió o eliminó correo ajeno.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlAud02'; Workload='AUDIT'
           Frameworks=@('ISO/IEC 27001 A.8.15'); License='E3' }

        @{ Id='PAV-AUD-03'; Domain='AUD'
           Title='Existen directivas de retención del registro de auditoría'
           Rationale='Sin directivas propias, todos los registros caducan en el periodo por defecto del plan, con independencia de su valor.'
           BusinessImpact='La evidencia desaparece antes de que muchas investigaciones lleguen a iniciarse.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlAud03'; Workload='AUDIT'
           Frameworks=@('NIST SP 800-53 AU-11'); License='E5' }

        @{ Id='PAV-AUD-04'; Domain='AUD'
           Title='La retención supera el periodo por defecto para los registros críticos'
           Rationale='Las investigaciones de fraude o de riesgo interno suelen abrirse mucho después del hecho.'
           BusinessImpact='La evidencia de actividades privilegiadas o sensibles se pierde antes de poder analizarse.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlAud04'; Workload='AUDIT'
           Frameworks=@('NIST SP 800-53 AU-11'); License='E5' }

        @{ Id='PAV-AUD-05'; Domain='AUD'
           Title='Las directivas de retención están correctamente distribuidas'
           Rationale='Una directiva cuya distribución no ha concluido todavía no aplica sobre los registros.'
           BusinessImpact='La retención declarada no se corresponde con la efectiva.'
           Severity='Baja'; Type='Technical'; Evaluator='Test-PavCtrlAud05'; Workload='AUDIT'
           Frameworks=@('NIST SP 800-53 AU-11'); License='E5' }

        @{ Id='PAV-AUD-06'; Domain='AUD'
           Title='Se revisa periódicamente quién consulta el registro de auditoría'
           Rationale='El acceso a la propia evidencia debe estar controlado: quien la consulta puede anticipar o encubrir una investigación.'
           BusinessImpact='No existe garantía sobre la integridad ni la confidencialidad del rastro de auditoría.'
           Severity='Media'; Type='Process'; Evaluator=''; Workload='AUDIT'
           Frameworks=@('NIST SP 800-53 AU-9'); License='E3' }

        # ── Descubrimiento electrónico ────────────────────────────────────────

        @{ Id='PAV-EDS-01'; Domain='EDS'
           Title='Existe capacidad de descubrimiento electrónico en uso'
           Rationale='La existencia de casos demuestra que la capacidad está operativa y no solo licenciada.'
           BusinessImpact='Ante un requerimiento legal, la organización improvisa el proceso de recolección sin experiencia previa.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlEds01'; Workload='EDS'
           Frameworks=@('ISO/IEC 27001 A.5.28'); License='E3' }

        @{ Id='PAV-EDS-02'; Domain='EDS'
           Title='Existen retenciones legales que preserven el contenido'
           Rationale='La retención legal congela el contenido en cuanto un litigio resulta previsible, antes de que las políticas de eliminación actúen.'
           BusinessImpact='La evidencia puede destruirse por las propias políticas de retención, con riesgo de destrucción indebida de prueba.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlEds02'; Workload='EDS'
           Frameworks=@('ISO/IEC 27001 A.5.28', 'NIST SP 800-53 AU-11'); License='E3' }

        @{ Id='PAV-EDS-03'; Domain='EDS'
           Title='Las retenciones legales alcanzan las ubicaciones donde reside la evidencia'
           Rationale='Una retención limitada a una carga deja fuera el resto del rastro documental del caso.'
           BusinessImpact='La preservación es parcial y la contraparte puede cuestionar la integridad de lo aportado.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlEds03'; Workload='EDS'
           Frameworks=@('ISO/IEC 27001 A.5.28'); License='E3' }

        @{ Id='PAV-EDS-04'; Domain='EDS'
           Title='El acceso a los casos está restringido a personal autorizado'
           Rationale='El contenido de un caso legal es de los datos más sensibles del tenant, y su acceso debe limitarse a quienes lo instruyen.'
           BusinessImpact='Personal ajeno a la función legal puede consultar información de litigios o investigaciones internas.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlEds04'; Workload='EDS'
           Frameworks=@('ISO/IEC 27001 A.5.15'); License='E3' }

        @{ Id='PAV-EDS-05'; Domain='EDS'
           Title='Existe un procedimiento documentado de respuesta a requerimientos'
           Rationale='La defensibilidad depende de seguir un proceso repetible y acreditable, no del conocimiento de una persona.'
           BusinessImpact='El tiempo de respuesta y la calidad de la entrega dependen de quién esté disponible.'
           Severity='Media'; Type='Process'; Evaluator=''; Workload='EDS'
           Frameworks=@('ISO/IEC 27001 A.5.28'); License='E3' }

        # ── Gobierno de inteligencia artificial ───────────────────────────────

        @{ Id='PAV-AI-01'; Domain='AI'
           Title='Las etiquetas de confidencialidad protegen el contenido accesible por la IA'
           Rationale='El asistente hereda los permisos del usuario: la etiqueta con cifrado es lo que impide que resuma contenido que el usuario no debería consultar.'
           BusinessImpact='La IA expone en sus respuestas información sensible que el usuario no habría localizado por sí mismo.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlAi01'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001', 'ISO/IEC 27001 A.5.12'); License='E5' }

        @{ Id='PAV-AI-02'; Domain='AI'
           Title='Existen directivas de prevención de pérdida de datos dirigidas a la IA'
           Rationale='El envío de información sensible en una petición al asistente es una vía de salida que las directivas convencionales no cubren.'
           BusinessImpact='Los usuarios trasladan datos regulados a la IA sin control ni registro.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlAi02'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001'); License='E5' }

        @{ Id='PAV-AI-03'; Domain='AI'
           Title='Las interacciones con la IA se conservan bajo una política de retención'
           Rationale='Las peticiones y respuestas son registros de negocio y pueden ser objeto de requerimiento legal.'
           BusinessImpact='La organización no puede aportar ni depurar de forma defendible el contenido generado por la IA.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlAi03'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001'); License='E5' }

        @{ Id='PAV-AI-04'; Domain='AI'
           Title='El uso de la IA está supervisado por cumplimiento de comunicaciones'
           Rationale='La interacción con el asistente es un canal más de comunicación y debe supervisarse como tal.'
           BusinessImpact='El uso indebido del asistente no se detecta ni se puede acreditar.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlAi04'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001'); License='E5' }

        @{ Id='PAV-AI-05'; Domain='AI'
           Title='El riesgo interno contempla el uso indebido de la IA'
           Rationale='La IA facilita agregar y extraer información a gran velocidad, un vector propio de exfiltración.'
           BusinessImpact='La extracción masiva mediante el asistente no genera señal de riesgo.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlAi05'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001'); License='E5' }

        @{ Id='PAV-AI-06'; Domain='AI'
           Title='Las interacciones con la IA se registran en la auditoría'
           Rationale='Sin registro de auditoría no es posible investigar qué se preguntó ni qué se respondió.'
           BusinessImpact='Las peticiones y respuestas no pueden investigarse ni aportarse ante un requerimiento.'
           Severity='Alta'; Type='Technical'; Evaluator='Test-PavCtrlAi06'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001', 'NIST SP 800-53 AU-2'); License='E5' }

        @{ Id='PAV-AI-07'; Domain='AI'
           Title='El contenido generado por la IA es localizable para descubrimiento electrónico'
           Rationale='Lo que no puede buscarse ni preservarse no puede aportarse en un procedimiento legal.'
           BusinessImpact='El contenido de la IA queda fuera del alcance de cualquier requerimiento, con riesgo de entrega incompleta.'
           Severity='Media'; Type='Technical'; Evaluator='Test-PavCtrlAi07'; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001'); License='E5' }

        @{ Id='PAV-AI-08'; Domain='AI'
           Title='El acceso a la IA está acotado a una población validada'
           Rationale='Un despliegue por fases permite validar los controles antes de exponer a toda la organización.'
           BusinessImpact='La exposición alcanza a todo el tenant antes de comprobar que la protección funciona.'
           Severity='Media'; Type='Process'; Evaluator=''; Workload='MULTI'
           Frameworks=@('ISO/IEC 42001'); License='E5' }
    )
}
