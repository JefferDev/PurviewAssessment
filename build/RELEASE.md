# Guía de release y firma — PurviewAssessment

## Pipeline de release (ejecutar en Windows con PS 7.2+)

```powershell
# 1. Validación completa (lo mismo que corre CI)
./build/Invoke-ReadOnlyGate.ps1 -ModulePath .
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./Tests

# 2. Versionado: actualizar ModuleVersion en el .psd1 y CHANGELOG.md (SemVer)

# 3. Firma Authenticode con sello de tiempo
#    (Invoke-Sign.ps1 re-ejecuta el gate y SE NIEGA a firmar si falla)

# 3a. LABORATORIO: certificado autofirmado (una sola vez)
$cert = New-SelfSignedCertificate -Subject 'CN=PurviewAssessment Lab' `
    -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My
# Confiar en el cert de lab (SOLO en equipos de prueba):
Export-Certificate -Cert $cert -FilePath .\lab.cer
Import-Certificate -FilePath .\lab.cer -CertStoreLocation Cert:\CurrentUser\Root
Import-Certificate -FilePath .\lab.cer -CertStoreLocation Cert:\CurrentUser\TrustedPublisher

./build/Invoke-Sign.ps1 -Thumbprint $cert.Thumbprint

# 3b. PRODUCCIÓN/CLIENTES: certificado comercial de Code Signing
#     (DigiCert/Sectigo/GlobalSign, confiado por defecto en Windows)
./build/Invoke-Sign.ps1 -Thumbprint '<huella-cert-comercial>'

# 4. Verificación de la firma
Get-ChildItem -Recurse -Include *.ps1,*.psd1,*.psm1 |
    Where-Object FullName -notmatch '\\(Tests|build)\\' |
    Get-AuthenticodeSignature |
    Group-Object Status | Format-Table Name, Count
# Esperado: todos 'Valid'. Con AllSigned: Import-Module pedirá confiar
# en el publisher la primera vez (cert comercial) o nunca (lab sin Root).

# 5. Empaquetar y etiquetar
Compress-Archive -Path .\PurviewAssessment -DestinationPath ".\PurviewAssessment-v<version>.zip"
git tag v<version> && git push --tags
```

## Notas
- La firma incluye timestamp (DigiCert): sigue válida tras expirar el cert.
- Invoke-Sign valida EKU de Code Signing (1.3.6.1.5.5.7.3.3) y expiración.
- El invariante de solo lectura queda certificado por la firma: no es posible
  firmar un build que invoque cmdlets de escritura sobre Purview.

## Distribución PRIVADA (Install-Module sin Galería pública)

La Galería pública no soporta paquetes privados. La experiencia privada se
logra hospedando un repositorio NuGet propio y registrándolo en cada máquina.

### Opción 1 — GitHub Packages (recomendada: mismo repo del código)

```powershell
# ── LADO PUBLICADOR (una vez por versión) ──
# PAT clásico con scopes: write:packages, read:packages
Register-PSResourceRepository -Name GHPrivado `
    -Uri 'https://nuget.pkg.github.com/jefferdev/index.json' -Trusted
./build/Publish-ToGallery.ps1 -Repository GHPrivado -ApiKey '<PAT>'

# ── LADO CONSUMIDOR (cada consultor, una vez) ──
# Requiere Microsoft.PowerShell.PSResourceGet (incluido en PS 7.4+)
Register-PSResourceRepository -Name GHPrivado `
    -Uri 'https://nuget.pkg.github.com/jefferdev/index.json' -Trusted
$cred = Get-Credential   # usuario: cuenta GitHub | contraseña: PAT con read:packages
Install-PSResource PurviewAssessment -Repository GHPrivado -Credential $cred
```
Los permisos del paquete heredan los del repositorio: repo privado = feed
privado; se puede dar acceso de solo lectura por usuario/equipo.

### Opción 2 — Azure DevOps Artifacts (estándar corporativo)

```powershell
# Feed en dev.azure.com → Artifacts → New feed (visibilidad por proyecto/organización)
Register-PSResourceRepository -Name SwoFeed `
    -Uri 'https://pkgs.dev.azure.com/<org>/_packaging/<feed>/nuget/v3/index.json' -Trusted
./build/Publish-ToGallery.ps1 -Repository SwoFeed -ApiKey '<PAT-con-Packaging-Read&Write>'
# Consumidor: mismo Register + Install-PSResource con PAT de solo lectura.
```

### Opción 3 — Carpeta compartida (equipos pequeños, cero infraestructura)

```powershell
Register-PSResourceRepository -Name SwoShare -Uri '\\servidor\PSModules' -Trusted
./build/Publish-ToGallery.ps1 -Repository SwoShare -ApiKey 'no-usada'
Install-PSResource PurviewAssessment -Repository SwoShare
```

Nota: con PowerShellGet v2 clásico (Publish-Module/Install-Module) las
opciones 2 y 3 funcionan igual; GitHub Packages requiere PSResourceGet por
su autenticación NuGet v3.
