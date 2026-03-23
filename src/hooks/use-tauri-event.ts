import { useEffect, useRef } from "react";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export function useTauriEvent<T>(event: string, handler: (payload: T) => void) {
  const handlerRef = useRef(handler);

  useEffect(() => {
    handlerRef.current = handler;
  }, [handler]);

  useEffect(() => {
    let unlisten: UnlistenFn | undefined;
    let disposed = false;

    const setup = async () => {
      const fn = await listen<T>(event, (e) => handlerRef.current(e.payload));

      if (disposed) {
        fn();
      } else {
        unlisten = fn;
      }
    };

    void setup();

    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [event]);
}
