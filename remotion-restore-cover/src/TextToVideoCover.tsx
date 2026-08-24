import {Video} from "@remotion/media";
import {
  AbsoluteFill,
  Composition,
  Easing,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const FPS = 30;
const WIDTH = 1280;
const HEIGHT = 720;
const DURATION_IN_FRAMES = 268;
const VIDEO_START = 86;
const WIPE_END = 112;

const PROMPT =
  "A giant whale flies between skyscrapers in a futuristic city at sunset.";

const PromptScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const typingStart = 12;
  const typingEnd = 78;
  const typedCharacters = Math.floor(
    interpolate(frame, [typingStart, typingEnd], [0, PROMPT.length], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.34, 0.01, 0.46, 1),
    }),
  );
  const wipeProgress = interpolate(frame, [VIDEO_START, WIPE_END], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.76, 0, 0.24, 1),
  });
  const cursorOpacity =
    typedCharacters === PROMPT.length
      ? interpolate(frame, [78, 83, 86], [1, 0.25, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        })
      : frame % 16 < 10
        ? 1
        : 0;
  const promptLift = interpolate(frame, [0, 20], [18, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  const promptOpacity = interpolate(frame, [0, 14], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: "#f7f8fa",
        color: "#101114",
        clipPath: `inset(0 0 0 ${wipeProgress * 100}%)`,
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: 0.22,
          backgroundImage:
            "radial-gradient(circle at 1px 1px, rgba(17, 18, 22, 0.17) 1px, transparent 0)",
          backgroundSize: "24px 24px",
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 84,
          top: 68,
          display: "flex",
          alignItems: "center",
          gap: 14,
          fontSize: 22,
          fontWeight: 750,
        }}
      >
        <div
          style={{
            width: 42,
            height: 42,
            borderRadius: 10,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: "white",
            backgroundColor: "#111216",
            fontSize: 16,
            fontWeight: 850,
          }}
        >
          AI
        </div>
        TEXT TO VIDEO
      </div>

      <div
        style={{
          position: "absolute",
          left: 84,
          right: 84,
          top: 176,
          height: 330,
          padding: "48px 54px",
          border: "2px solid #dedfe3",
          borderRadius: 26,
          backgroundColor: "rgba(255, 255, 255, 0.96)",
          boxShadow: "0 26px 70px rgba(24, 29, 39, 0.1)",
          opacity: promptOpacity,
          transform: `translateY(${promptLift}px)`,
        }}
      >
        <div
          style={{
            marginBottom: 28,
            color: "#777b84",
            fontSize: 18,
            fontWeight: 650,
          }}
        >
          DESCRIBE YOUR VIDEO
        </div>
        <div
          style={{
            maxWidth: 1010,
            fontSize: 49,
            lineHeight: 1.18,
            fontWeight: 720,
            letterSpacing: 0,
          }}
        >
          {PROMPT.slice(0, typedCharacters)}
          <span
            style={{
              display: "inline-block",
              width: 4,
              height: 50,
              marginLeft: 5,
              borderRadius: 2,
              verticalAlign: -7,
              backgroundColor: "#5b5ef4",
              opacity: cursorOpacity,
            }}
          />
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          left: 84,
          bottom: 76,
          color: "#686c75",
          fontSize: 20,
          fontWeight: 600,
        }}
      >
        Type one sentence. Watch it come alive.
      </div>

      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: wipeProgress * width - 70,
          width: 140,
          opacity: wipeProgress > 0 && wipeProgress < 1 ? 1 : 0,
          background:
            "linear-gradient(90deg, transparent, rgba(255,255,255,0.92), rgba(170,230,255,0.92), rgba(255,255,255,0.98), transparent)",
          filter: "blur(10px)",
          transform: "skewX(-9deg)",
          boxShadow: "0 0 70px 25px rgba(113, 207, 255, 0.5)",
        }}
      />
    </AbsoluteFill>
  );
};

const ResultScene: React.FC = () => {
  const frame = useCurrentFrame();
  const reveal = interpolate(frame, [0, WIPE_END - VIDEO_START], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.76, 0, 0.24, 1),
  });
  const scale = interpolate(frame, [0, DURATION_IN_FRAMES - VIDEO_START], [1.025, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const flashOpacity = interpolate(frame, [14, 22, 29], [0, 0.64, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{backgroundColor: "#080d12", overflow: "hidden"}}>
      <Video
        src={staticFile("whale-city.mp4")}
        muted
        objectFit="cover"
        style={{
          width: "100%",
          height: "100%",
          transform: `scale(${scale})`,
        }}
      />
      <AbsoluteFill
        style={{
          opacity: reveal < 0.96 ? 0.14 : 0,
          background:
            "linear-gradient(90deg, rgba(84,185,255,0.24), transparent 42%)",
        }}
      />
      <AbsoluteFill
        style={{
          opacity: flashOpacity,
          backgroundColor: "white",
          mixBlendMode: "screen",
        }}
      />
    </AbsoluteFill>
  );
};

export const TextToVideoCover: React.FC = () => {
  return (
    <AbsoluteFill style={{backgroundColor: "#080d12"}}>
      <Sequence from={VIDEO_START} premountFor={FPS}>
        <ResultScene />
      </Sequence>
      <PromptScene />
    </AbsoluteFill>
  );
};

export const TextToVideoCoverComposition: React.FC = () => {
  return (
    <Composition
      id="TextToVideoWhaleCover"
      component={TextToVideoCover}
      durationInFrames={DURATION_IN_FRAMES}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  );
};
