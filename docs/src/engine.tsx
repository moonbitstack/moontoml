import { useEffect, useState } from "react";

/* The library, compiled to JavaScript by the docs workflow. A page never
   reimplements what it shows: every verdict on these pages is a call into it. */
export type Engine = {
  inspect(src: string, sort: boolean): string;
  editions(src: string): string;
  kept(src: string, path: string, value: string): string;
  fault(src: string, edition: number): string;
  fault_bytes(bytes: Uint8Array, edition: number): string;
};

declare global {
  interface Window {
    moontoml?: Engine;
  }
}

export function useEngine(): Engine | undefined {
  const [engine, setEngine] = useState<Engine | undefined>(() =>
    typeof window === "undefined" ? undefined : window.moontoml,
  );
  useEffect(() => {
    if (engine) return;
    const ready = () => setEngine(window.moontoml);
    addEventListener("moontoml:ready", ready);
    return () => removeEventListener("moontoml:ready", ready);
  }, [engine]);
  return engine;
}
