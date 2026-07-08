import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Pallet OS Admin",
  description: "Self-hosted Chromebook fleet management",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
