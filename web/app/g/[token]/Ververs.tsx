"use client";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

/** Haalt de pagina elke 10 s opnieuw op (alleen als het tabblad zichtbaar is). */
export default function Ververs() {
  const router = useRouter();
  useEffect(() => {
    const id = setInterval(() => {
      if (document.visibilityState === "visible") router.refresh();
    }, 10_000);
    return () => clearInterval(id);
  }, [router]);
  return <span className="live">Live</span>;
}
