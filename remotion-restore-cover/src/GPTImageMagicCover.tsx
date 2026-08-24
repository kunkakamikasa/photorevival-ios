import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  random,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const RESET_START = 1;
const SOURCE_ENTER_START = 1.4;
const SOURCE_ENTER_END = 2.08;
const ARROW_START = 2.23;
const ARROW_END = 2.67;
const MAGIC_START = 3.08;
const REVEAL_START = 3.32;
const REVEAL_END = 4.02;

const clamp = (value: number) => Math.min(1, Math.max(0, value));

const particles = Array.from({ length: 84 }, (_, index) => ({
  delay: random(`gpt-particle-delay-${index}`) * 0.54,
  duration: 0.42 + random(`gpt-particle-duration-${index}`) * 0.52,
  startX: 130 + random(`gpt-particle-x-${index}`) * 360,
  travelX: 480 + random(`gpt-particle-travel-${index}`) * 620,
  y: 80 + random(`gpt-particle-y-${index}`) * 530,
  driftY: (random(`gpt-particle-drift-${index}`) - 0.5) * 110,
  size: 3 + random(`gpt-particle-size-${index}`) * 12,
  blur: random(`gpt-particle-blur-${index}`) * 2.4,
  warmth: random(`gpt-particle-warmth-${index}`),
}));

const SourcePhoto: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const resetFrame = RESET_START * fps;
  const enter = interpolate(frame, [SOURCE_ENTER_START * fps, SOURCE_ENTER_END * fps], [0, 1], {
    easing: Easing.bezier(0.18, 0.92, 0.28, 1.16),
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const isCompletedState = frame < resetFrame;
  const progress = isCompletedState ? 1 : enter;
  const opacity = isCompletedState ? 1 : interpolate(enter, [0, 0.12, 1], [0, 1, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const settleFrame = Math.max(0, frame - SOURCE_ENTER_END * fps);
  const floatY = progress === 1 ? Math.sin(settleFrame / (fps * 0.72)) * 3 : 0;
  const floatRotation = progress === 1 ? Math.sin(settleFrame / (fps * 0.95)) * 0.7 : 0;
  const x = interpolate(progress, [0, 1], [-190, 74]);
  const y = interpolate(progress, [0, 1], [-230, 62]) + floatY;
  const rotation = interpolate(progress, [0, 1], [-18, -6]) + floatRotation;
  const scale = interpolate(progress, [0, 1], [0.58, 1]);

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: 222,
        height: 334,
        padding: 9,
        borderRadius: 8,
        backgroundColor: "#f4c94e",
        boxShadow: "0 22px 48px rgba(0, 0, 0, 0.5), 0 0 26px rgba(255, 213, 76, 0.35)",
        opacity,
        transform: `translate3d(${x}px, ${y}px, 0) rotate(${rotation}deg) scale(${scale})`,
        transformOrigin: "center",
      }}
    >
      <Img src={staticFile("gpt-image-source.png")} style={{ width: "100%", height: "100%", display: "block", objectFit: "cover", borderRadius: 3 }} />
      <div style={{ position: "absolute", inset: 9, border: "2px solid rgba(255, 255, 255, 0.58)", borderRadius: 3 }} />
    </div>
  );
};

const HandDrawnArrow: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const resetFrame = RESET_START * fps;
  const draw = frame < resetFrame ? 1 : interpolate(frame, [ARROW_START * fps, ARROW_END * fps], [0, 1], {
    easing: Easing.inOut(Easing.cubic), extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });

  return (
    <svg viewBox="0 0 1280 720" style={{ position: "absolute", inset: 0, width: "100%", height: "100%", overflow: "visible", opacity: draw === 0 ? 0 : 1 }}>
      <defs><filter id="arrow-glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter></defs>
      <path d="M 286 198 C 342 168, 405 183, 413 225 C 421 266, 467 276, 523 240" fill="none" pathLength={1} stroke="rgba(0, 0, 0, 0.42)" strokeDasharray={1} strokeDashoffset={1 - draw} strokeLinecap="round" strokeWidth={17} transform="translate(4 5)" />
      <path d="M 286 198 C 342 168, 405 183, 413 225 C 421 266, 467 276, 523 240" fill="none" filter="url(#arrow-glow)" pathLength={1} stroke="#ffd12f" strokeDasharray={1} strokeDashoffset={1 - draw} strokeLinecap="round" strokeWidth={11} />
      <path d="M 482 226 L 524 240 L 496 274" fill="none" filter="url(#arrow-glow)" pathLength={1} stroke="#ffd12f" strokeDasharray={1} strokeDashoffset={1 - clamp((draw - 0.78) / 0.22)} strokeLinecap="round" strokeLinejoin="round" strokeWidth={11} />
    </svg>
  );
};

const MagicParticles: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill style={{ overflow: "hidden", mixBlendMode: "screen" }}>
      {particles.map((particle, index) => {
        const start = (MAGIC_START + particle.delay) * fps;
        const end = start + particle.duration * fps;
        const progress = interpolate(frame, [start, end], [0, 1], { easing: Easing.out(Easing.cubic), extrapolateLeft: "clamp", extrapolateRight: "clamp" });
        const opacity = interpolate(progress, [0, 0.12, 0.58, 1], [0, 0.96, 0.72, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
        const x = particle.startX + particle.travelX * progress;
        const y = particle.y + particle.driftY * progress;
        const color = particle.warmth > 0.62 ? "rgba(255, 247, 198, 0.98)" : "rgba(255, 191, 52, 0.96)";
        return <div key={index} style={{ position: "absolute", left: x, top: y, width: particle.size, height: particle.size, borderRadius: "50%", backgroundColor: color, boxShadow: `0 0 ${12 + particle.size * 2}px ${color}`, filter: `blur(${particle.blur}px)`, opacity, transform: `scale(${interpolate(progress, [0, 0.35, 1], [0.3, 1.25, 0.15])})` }} />;
      })}
    </AbsoluteFill>
  );
};

const MagicSweep: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const progress = interpolate(frame, [MAGIC_START * fps, (REVEAL_END + 0.08) * fps], [0, 1], { easing: Easing.inOut(Easing.cubic), extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const opacity = interpolate(progress, [0, 0.12, 0.72, 1], [0, 0.9, 0.78, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const x = interpolate(progress, [0, 1], [-530, 1460]);
  return (
    <AbsoluteFill style={{ overflow: "hidden", mixBlendMode: "screen" }}>
      <div style={{ position: "absolute", left: x, top: -250, width: 430, height: 1220, opacity, transform: "rotate(-17deg)", background: "linear-gradient(90deg, rgba(255, 187, 20, 0), rgba(255, 193, 36, 0.34) 23%, rgba(255, 255, 226, 0.98) 51%, rgba(255, 194, 45, 0.42) 73%, rgba(255, 187, 20, 0))", filter: "blur(18px)", boxShadow: "0 0 90px 28px rgba(255, 195, 48, 0.38)" }} />
      <div style={{ position: "absolute", left: x + 92, top: 68, width: 210, height: 570, opacity: opacity * 0.86, transform: "rotate(-17deg)", background: "linear-gradient(90deg, rgba(255,255,255,0), rgba(255,255,236,0.98), rgba(255,255,255,0))", filter: "blur(5px)" }} />
    </AbsoluteFill>
  );
};

export const GPTImageMagicCover: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const resetFrame = RESET_START * fps;
  const resetOverlay = interpolate(frame, [resetFrame, resetFrame + 3], [0, 0.7], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const reveal = interpolate(frame, [REVEAL_START * fps, REVEAL_END * fps], [0, 1], { easing: Easing.bezier(0.42, 0, 0.22, 1), extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const completedAtLoopStart = frame < resetFrame;
  const overlayOpacity = completedAtLoopStart ? 0 : resetOverlay * (1 - reveal);
  const magicBlackout = interpolate(frame, [3 * fps, 3.08 * fps, 3.2 * fps, 3.52 * fps], [0, 0.3, 0.3, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const loopProgress = frame / Math.max(1, durationInFrames - 1);
  const backgroundScale = 1.012 + (1 - Math.cos(loopProgress * Math.PI * 2)) * 0.004;

  return (
    <AbsoluteFill style={{ backgroundColor: "#080806", color: "white", fontFamily: '"Helvetica Neue", Arial, sans-serif', overflow: "hidden" }}>
      <Img src={staticFile("gpt-image-result.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", objectPosition: "center 47%", transform: `scale(${backgroundScale})` }} />
      <AbsoluteFill style={{ backgroundColor: "rgba(3, 7, 5, 1)", opacity: overlayOpacity }} />
      <AbsoluteFill style={{ backgroundColor: "rgba(0, 0, 0, 1)", opacity: magicBlackout }} />
      <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(0,0,0,0.12) 0%, rgba(0,0,0,0) 42%, rgba(0,0,0,0.46) 100%)" }} />
      <SourcePhoto />
      <HandDrawnArrow />
      <MagicParticles />
      <MagicSweep />
      <div style={{ position: "absolute", left: 330, right: 42, bottom: 102, textAlign: "center", textShadow: "0 3px 12px rgba(0,0,0,0.92)" }}>
        <div style={{ fontSize: 78, lineHeight: 0.98, fontWeight: 800, whiteSpace: "nowrap" }}>GPT-IMAGE 2.0</div>
        <div style={{ marginTop: 20, color: "#f6c348", fontSize: 28, lineHeight: 1, fontWeight: 600, whiteSpace: "nowrap" }}>Use advanced AI to transform your images</div>
      </div>
      <AbsoluteFill style={{ boxShadow: "inset 0 0 80px rgba(0, 0, 0, 0.3)", pointerEvents: "none" }} />
    </AbsoluteFill>
  );
};
