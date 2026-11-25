param(
    [string]$DeviceName = "BluePad",
    [int]$ScanSeconds = 15
)

$ErrorActionPreference = "Stop"

# 1. Check that Windows Bluetooth radio is present and turned ON
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await-WinRT {
    param($WinRtTask, [Type]$ResultType)
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    return $netTask.Result
}

$null = [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
$radios = Await-WinRT ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
$btRadio = $radios | Where-Object { $_.Kind -eq 'Bluetooth' } | Select-Object -First 1

if (-not $btRadio) {
    Write-Host "HATA: Bu bilgisayarda Bluetooth radyosu bulunamadi." -ForegroundColor Red
    exit 1
}
if ($btRadio.State -ne 'On') {
    Write-Host "HATA: Windows Bluetooth kapali (Durum: $($btRadio.State)). Lutfen Bluetooth'u acin." -ForegroundColor Red
    exit 1
}

$null = [Windows.Devices.Bluetooth.BluetoothAdapter, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$adapter = Await-WinRT ([Windows.Devices.Bluetooth.BluetoothAdapter]::GetDefaultAsync()) ([Windows.Devices.Bluetooth.BluetoothAdapter])
if (-not $adapter -or -not $adapter.IsLowEnergySupported -or -not $adapter.IsCentralRoleSupported) {
    Write-Host "HATA: Bluetooth adaptoru BLE Central rolunu desteklemiyor." -ForegroundColor Red
    exit 1
}

Write-Host "Windows Bluetooth hazir. iPhone'da BluePad ekranini acik tutup '$DeviceName' taraniyor ($ScanSeconds sn)..." -ForegroundColor Cyan

# 2. Compile in-memory WinRT BLE HID pairing helper (no .AsTask() to avoid Windows.winmd facade issue)
$winmdDir = "$env:SystemRoot\System32\WinMetadata"
$fxDir = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319"

$cp = New-Object System.CodeDom.Compiler.CompilerParameters
$cp.GenerateInMemory = $true
$cp.ReferencedAssemblies.Add("System.dll") | Out-Null
$cp.ReferencedAssemblies.Add("System.Core.dll") | Out-Null
$cp.ReferencedAssemblies.Add("System.Runtime.dll") | Out-Null
$cp.ReferencedAssemblies.Add("$fxDir\System.Runtime.WindowsRuntime.dll") | Out-Null
$cp.ReferencedAssemblies.Add("$fxDir\System.Runtime.InteropServices.WindowsRuntime.dll") | Out-Null
$cp.ReferencedAssemblies.Add("$winmdDir\Windows.Foundation.winmd") | Out-Null
$cp.ReferencedAssemblies.Add("$winmdDir\Windows.Devices.winmd") | Out-Null
$cp.ReferencedAssemblies.Add("$winmdDir\Windows.Storage.winmd") | Out-Null

$csharpSource = @'
using System;
using System.Threading;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Enumeration;
using Windows.Foundation;

public static class BluePadWinPair {
    private const string HidServiceUuid = "00001812-0000-1000-8000-00805f9b34fb";

    public static bool Run(string targetName, int scanSeconds) {
        string cleanTarget = string.IsNullOrWhiteSpace(targetName) ? "BluePad" : targetName.Trim();
        int timeoutMs = Math.Max(3, scanSeconds) * 1000;

        ulong foundAddr = 0;
        string foundName = "";
        short foundRssi = -127;
        ulong fallbackAddr = 0;
        string fallbackName = "";
        short fallbackRssi = -127;
        var foundEvt = new ManualResetEventSlim(false);
        object sync = new object();

        var watcher = new BluetoothLEAdvertisementWatcher();
        watcher.ScanningMode = BluetoothLEScanningMode.Active;

        TypedEventHandler<BluetoothLEAdvertisementWatcher, BluetoothLEAdvertisementReceivedEventArgs> advHandler = (s, a) => {
            string name = a.Advertisement.LocalName ?? "";
            bool hasHid = false;
            foreach (var u in a.Advertisement.ServiceUuids) {
                if (u.ToString().Equals(HidServiceUuid, StringComparison.OrdinalIgnoreCase)) {
                    hasHid = true;
                    break;
                }
            }
            bool exactMatch = !string.IsNullOrWhiteSpace(name) && name.Equals(cleanTarget, StringComparison.OrdinalIgnoreCase);
            if (exactMatch) {
                lock (sync) {
                    if (foundAddr == 0) {
                        foundAddr = a.BluetoothAddress;
                        foundName = name;
                        foundRssi = a.RawSignalStrengthInDBm;
                        foundEvt.Set();
                    }
                }
            } else if (hasHid) {
                lock (sync) {
                    if (fallbackAddr == 0) {
                        fallbackAddr = a.BluetoothAddress;
                        fallbackName = name;
                        fallbackRssi = a.RawSignalStrengthInDBm;
                    }
                }
            }
        };

        watcher.Received += advHandler;
        watcher.Start();
        int firstWait = Math.Min(4000, timeoutMs);
        foundEvt.Wait(firstWait);
        if (foundAddr == 0 && timeoutMs > firstWait && fallbackAddr == 0) {
            foundEvt.Wait(timeoutMs - firstWait);
        }
        watcher.Stop();
        watcher.Received -= advHandler;

        if (foundAddr == 0 && fallbackAddr != 0) {
            foundAddr = fallbackAddr;
            foundName = fallbackName;
            foundRssi = fallbackRssi;
        }

        if (foundAddr == 0) {
            Console.WriteLine("BULUNAMADI: BLE yayini gorunmedi. iPhone ekraninin acik ve BluePad'in on planda oldugunu kontrol edin.");
            Console.Out.Flush();
            return false;
        }

        Console.WriteLine(string.Format("BULUNDU: Adres={0:X12} Ad='{1}' RSSI={2} dBm", foundAddr, foundName, foundRssi));
        Console.Out.Flush();

        var devDone = new ManualResetEventSlim(false);
        var devOp = BluetoothLEDevice.FromBluetoothAddressAsync(foundAddr);
        devOp.Completed = (info, status) => devDone.Set();
        if (!devDone.Wait(15000)) {
            Console.WriteLine("HATA: Bluetooth aygitina baglanirken zaman asimi olustu.");
            Console.Out.Flush();
            return false;
        }
        if (devOp.Status != AsyncStatus.Completed) {
            Console.WriteLine("HATA: Aygit acilamadi (" + devOp.Status + " / " + devOp.ErrorCode + ")");
            Console.Out.Flush();
            return false;
        }

        var dev = devOp.GetResults();
        if (dev == null) {
            Console.WriteLine("HATA: BluetoothLEDevice null dondu.");
            Console.Out.Flush();
            return false;
        }

        var pairing = dev.DeviceInformation.Pairing;
        Console.WriteLine(string.Format("CIHAZ: Ad='{0}' Esli={1} Eslesebilir={2}",
            dev.Name ?? "", pairing.IsPaired, pairing.CanPair));
        Console.Out.Flush();

        if (pairing.IsPaired) {
            Console.WriteLine("DURUM: Cihaz Windows ile zaten eslesmis (AlreadyPaired).");
            Console.Out.Flush();
            dev.Dispose();
            return true;
        }

        var custom = pairing.Custom;
        TypedEventHandler<DeviceInformationCustomPairing, DevicePairingRequestedEventArgs> reqHandler = (sender, args) => {
            string pin = "";
            try { pin = args.Pin ?? ""; } catch {}
            if (string.IsNullOrEmpty(pin)) {
                Console.WriteLine("ESLEME ISTEGI (" + args.PairingKind + "): iPhone ekraninda 'Esle' butonuna dokunun.");
            } else {
                Console.WriteLine("ESLEME ISTEGI (" + args.PairingKind + ") PIN=" + pin + ": iPhone ekraninda bu kodu onaylayip 'Esle'ye dokunun.");
            }
            Console.Out.Flush();
            if (args.PairingKind == DevicePairingKinds.ConfirmOnly || args.PairingKind == DevicePairingKinds.ConfirmPinMatch) {
                args.Accept();
            }
        };
        custom.PairingRequested += reqHandler;

        bool isPairedNow = false;
        DevicePairingResultStatus finalStatus = DevicePairingResultStatus.Failed;
        try {
            finalStatus = TryPair(custom, DevicePairingProtectionLevel.EncryptionAndAuthentication, "1. Deneme (Sifreli + Dogrulamali)");
            if (finalStatus == DevicePairingResultStatus.Paired || finalStatus == DevicePairingResultStatus.AlreadyPaired) {
                isPairedNow = true;
            } else if (finalStatus == DevicePairingResultStatus.ProtectionLevelCouldNotBeMet) {
                finalStatus = TryPair(custom, DevicePairingProtectionLevel.Encryption, "2. Deneme (Sifreli)");
                isPairedNow = (finalStatus == DevicePairingResultStatus.Paired || finalStatus == DevicePairingResultStatus.AlreadyPaired);
            }
            if (!isPairedNow && (finalStatus == DevicePairingResultStatus.Failed || finalStatus == DevicePairingResultStatus.AuthenticationFailure || finalStatus == DevicePairingResultStatus.RejectedByHandler)) {
                Console.WriteLine("IPUCU: Daha once bu PC ile eslestiyseniz, iPhone Ayarlar -> Bluetooth ekranindan bilgisayari ('Bu Aygiti Unut') kaldirip tekrar deneyin.");
                Console.Out.Flush();
            }
        } finally {
            custom.PairingRequested -= reqHandler;
        }

        dev.Dispose();
        return isPairedNow;
    }

    private static DevicePairingResultStatus TryPair(DeviceInformationCustomPairing custom, DevicePairingProtectionLevel level, string label) {
        var done = new ManualResetEventSlim(false);
        var op = custom.PairAsync(DevicePairingKinds.ConfirmOnly | DevicePairingKinds.ConfirmPinMatch, level);
        op.Completed = (info, status) => done.Set();

        if (!done.Wait(45000)) {
            Console.WriteLine(label + " -> Zaman asimi (45s)");
            Console.Out.Flush();
            return DevicePairingResultStatus.AuthenticationTimeout;
        }
        if (op.Status != AsyncStatus.Completed) {
            Console.WriteLine(label + " -> AsyncStatus=" + op.Status + " Error=" + op.ErrorCode);
            Console.Out.Flush();
            return DevicePairingResultStatus.Failed;
        }
        var res = op.GetResults();
        Console.WriteLine(label + " -> Sonuc=" + res.Status + " Koruma=" + res.ProtectionLevelUsed);
        Console.Out.Flush();
        return res.Status;
    }
}
'@

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$compileResult = $provider.CompileAssemblyFromSource($cp, $csharpSource)
if ($compileResult.Errors.HasErrors) {
    foreach ($err in $compileResult.Errors) {
        Write-Host $err.ToString() -ForegroundColor Red
    }
    exit 1
}

$helperType = $compileResult.CompiledAssembly.GetType("BluePadWinPair")
$paired = [bool]$helperType.GetMethod("Run").Invoke($null, @($DeviceName, $ScanSeconds))

if (-not $paired) {
    Write-Host "Eslestirme tamamlanamadi." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nWindows PnP HID suruculerinin yuklenmesi bekleniyor (4 sn)..." -ForegroundColor Cyan
Start-Sleep -Seconds 4

Write-Host "`n=== Windows 0x1812 BLE HID Servisleri ===" -ForegroundColor Green
Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'BTHLEDEVICE\\\{00001812' } |
    Format-Table Status, Class, FriendlyName, InstanceId -AutoSize

Write-Host "=== Bagli HID Aygıtları (Klavye / Fare / Medya / Gamepad) ===" -ForegroundColor Green
$hidDevs = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'HID\\\{00001812|BTHLE\\DEV_' }
$hidDevs | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize

$hidCollections = @($hidDevs | Where-Object { $_.InstanceId -match 'HID\\\{00001812' })
if ($hidCollections.Count -eq 0) {
    Write-Host "UYARI: Cihaz esli gorunse de Windows HID (0x1812) aygitlari henuz yuklenmedi." -ForegroundColor Yellow
    Write-Host "iPhone Ayarlar -> Bluetooth -> 'Bu Aygiti Unut' + Windows Ayarlar -> Cihazi Kaldir yapip tekrar eslestirin." -ForegroundColor Yellow
    exit 1
}
