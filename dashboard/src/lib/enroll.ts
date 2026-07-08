import { getApiUrl } from "./api";

export function buildSetupCommand(enrollmentToken: string): string {
  const serverUrl = getApiUrl();
  return `sudo apt update && sudo apt install -y git
git clone https://github.com/jackh54/Pallet-OS.git
cd Pallet-OS
sudo PALLET_SERVER_URL="${serverUrl}" \\
     PALLET_ENROLLMENT_TOKEN="${enrollmentToken}" \\
     ./provision/install-pallet-os.sh
sudo reboot`;
}

export function buildEnrollOnlyCommand(enrollmentToken: string): string {
  const serverUrl = getApiUrl();
  return `cd Pallet-OS
sudo PALLET_SERVER_URL="${serverUrl}" \\
     PALLET_ENROLLMENT_TOKEN="${enrollmentToken}" \\
     ./provision/enroll-device.sh`;
}

export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}
