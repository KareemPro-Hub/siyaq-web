type Name = "book" | "quote" | "check" | "leaf" | "search" | "arrow";
export function BrandIcon({name}: {name: Name}) {
  return <svg viewBox={name === "arrow" ? "0 0 24 24" : "0 0 32 32"} aria-hidden="true">
    {name === "book" && <><path d="M16 8C12 4 6 4 2 6v19c5-2 10-1 14 3 4-4 9-5 14-3V6c-4-2-10-2-14 2Z"/><path d="M16 8v20M6 10c2-1 5 0 7 1M6 15c2-1 5 0 7 1M19 11c2-1 5-2 7-1M19 16c2-1 5-2 7-1"/></>}
    {name === "quote" && <><path d="M7 7h18a3 3 0 0 1 3 3v13a3 3 0 0 1-3 3H13l-7 4v-4H7a3 3 0 0 1-3-3V10a3 3 0 0 1 3-3Z"/><path d="M11 13h5v5h-5v-5Zm8 0h4v5h-4v-5Z"/></>}
    {name === "check" && <><path d="M16 3 27 7v9c0 6-6 10-11 13C11 26 5 22 5 16V7l11-4Z"/><path d="m10 16 4 4 8-8"/></>}
    {name === "leaf" && <><path d="M6 26C3 15 11 4 26 5c1 15-9 24-20 21Z"/><path d="M6 26 23 9M10 21v-6M15 17h7"/></>}
    {name === "search" && <><circle cx="14" cy="14" r="9"/><path d="m21 21 7 7"/></>}
    {name === "arrow" && <path d="M19 12H5m6-6-6 6 6 6"/>}
  </svg>;
}
