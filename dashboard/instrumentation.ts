export async function register() {
  // Node.js 22+ ships a partial localStorage stub without getItem/setItem.
  // Patch it so SSR-imported client packages don't crash.
  if (
    typeof global !== "undefined" &&
    (typeof (global as unknown as Record<string, unknown>).localStorage === "undefined" ||
      typeof (global as unknown as Record<string, Storage>).localStorage?.getItem !== "function")
  ) {
    const store: Record<string, string> = {}
    ;(global as unknown as Record<string, Storage>).localStorage = {
      getItem: (k: string) => store[k] ?? null,
      setItem: (k: string, v: string) => { store[k] = v },
      removeItem: (k: string) => { delete store[k] },
      clear: () => { for (const k in store) delete store[k] },
      key: (i: number) => Object.keys(store)[i] ?? null,
      get length() { return Object.keys(store).length },
    }
  }
}
