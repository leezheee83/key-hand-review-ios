import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const protocol = requestHeaders.get("x-forwarded-proto") ?? "https";
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host") ?? "localhost:3000";
  const baseURL = `${protocol}://${host}`;
  const title = "手牌复盘速记";
  const description = "线下现金局关键手牌速记与复盘，数据只保存在本机。";

  return {
    title,
    description,
    manifest: "/manifest.webmanifest",
    appleWebApp: {
      capable: true,
      title: "手牌复盘",
      statusBarStyle: "black-translucent",
    },
    icons: {
      icon: "/icon-192.png",
      apple: "/icon-192.png",
    },
    openGraph: {
      title,
      description,
      type: "website",
      images: [{ url: `${baseURL}/og.png`, width: 1536, height: 1024, alt: "手牌复盘速记" }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [`${baseURL}/og.png`],
    },
  };
}

export const viewport: Viewport = {
  themeColor: "#102b2b",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
