import { useRef, useEffect } from "react";
import { Game } from "./game";

export default function Page() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) {
      return;
    }

    canvas.width = canvas.getBoundingClientRect().width;
    canvas.height = canvas.getBoundingClientRect().height;

    let running = true;
    const game = new Game(canvas.width, canvas.height);
    const render = (lastRenderedAt: number) => {
      if (!running) {
        return;
      }

      const now = Date.now();
      game.tick(now - lastRenderedAt);
      game.render(canvas, ctx);
      requestAnimationFrame(() => render(now));
    };

    requestAnimationFrame(render.bind(null, Date.now()));

    return () => {
      running = false;
    };
  }, []);

  return (
    <canvas
      style={{
        height: "100%",
        width: "100%",
        position: "absolute",
        top: "0",
        left: "0",
      }}
      ref={canvasRef}
    />
  );
}
