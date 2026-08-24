import {
  AbsoluteFill,
  Composition,
  Easing,
  Freeze,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Video } from "@remotion/media";

const FPS = 30;
const DURATION_SECONDS = 4;
const WIDTH = 1280;
const HEIGHT = 720;
const ENHANCE_FPS = 24;
const ENHANCE_DURATION_FRAMES = 145;
const PHOTO_ENHANCE_FPS = 30;
const PHOTO_ENHANCE_DURATION_FRAMES = 168;

type EnhanceVideoLayerProps = {
  src: string;
  clipPath?: string;
  resetOpacity: number;
};

const EnhanceVideoLayer: React.FC<EnhanceVideoLayerProps> = ({
  src,
  clipPath,
  resetOpacity,
}) => {
  const videoStyle: React.CSSProperties = {
    position: "absolute",
    inset: 0,
    width: "100%",
    height: "100%",
    objectFit: "cover",
    clipPath,
  };

  return (
    <>
      <Video src={src} muted style={videoStyle} />
      <Freeze frame={0}>
        <Video
          src={src}
          muted
          style={{ ...videoStyle, opacity: resetOpacity }}
        />
      </Freeze>
    </>
  );
};

export const RestoreComparisonCover: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames, width } = useVideoConfig();

  // A cosine wave reaches both ends gently and joins seamlessly when looped.
  const loopProgress = frame / (durationInFrames - 1);
  const sweepProgress = (1 - Math.cos(loopProgress * Math.PI * 2)) / 2;
  const edgeInset = width * 0.018;
  const dividerX = edgeInset + sweepProgress * (width - edgeInset * 2);

  return (
    <AbsoluteFill style={{ backgroundColor: "#111111", overflow: "hidden" }}>
      <Img
        src={staticFile("old-photo.png")}
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          objectFit: "cover",
        }}
      />
      <Img
        src={staticFile("restored-photo.png")}
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          objectFit: "cover",
          clipPath: `inset(0 0 0 ${dividerX}px)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: dividerX - 2,
          width: 4,
          backgroundColor: "rgba(255, 255, 255, 0.98)",
          boxShadow:
            "-2px 0 5px rgba(0, 0, 0, 0.38), 2px 0 5px rgba(0, 0, 0, 0.38), 0 0 10px rgba(255, 255, 255, 0.42)",
        }}
      />
    </AbsoluteFill>
  );
};

export const RestoreCoverComposition: React.FC = () => {
  return (
    <Composition
      id="RestoreComparisonCover"
      component={RestoreComparisonCover}
      durationInFrames={DURATION_SECONDS * FPS}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  );
};

export const EnhanceVideoComparisonCover: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames, width } = useVideoConfig();

  // The same source frame is rendered twice, so the comparison stays locked
  // while the divider reveals the restored/high-definition side.
  const loopProgress = frame / durationInFrames;
  const sweepProgress = (1 - Math.cos(loopProgress * Math.PI * 2)) / 2;
  const edgeInset = width * 0.018;
  const dividerX = edgeInset + sweepProgress * (width - edgeInset * 2);

  const resetOpacity = interpolate(
    frame,
    [durationInFrames - Math.round(0.42 * ENHANCE_FPS), durationInFrames - 1],
    [0, 1],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    },
  );

  return (
    <AbsoluteFill style={{ backgroundColor: "#111111", overflow: "hidden" }}>
      <EnhanceVideoLayer
        src={staticFile("enhance-low-quality.mp4")}
        resetOpacity={resetOpacity}
      />
      <EnhanceVideoLayer
        src={staticFile("enhance-hd.mp4")}
        resetOpacity={resetOpacity}
        clipPath={`inset(0 0 0 ${dividerX}px)`}
      />
      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: dividerX - 2,
          width: 4,
          backgroundColor: "rgba(255, 255, 255, 0.98)",
          boxShadow:
            "-2px 0 5px rgba(0, 0, 0, 0.38), 2px 0 5px rgba(0, 0, 0, 0.38), 0 0 10px rgba(255, 255, 255, 0.42)",
        }}
      />
    </AbsoluteFill>
  );
};

export const EnhanceVideoComparisonComposition: React.FC = () => {
  return (
    <Composition
      id="EnhanceVideoComparisonCover"
      component={EnhanceVideoComparisonCover}
      durationInFrames={ENHANCE_DURATION_FRAMES}
      fps={ENHANCE_FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  );
};

const interpolateSweepWithCenterPause = (
  frame: number,
  width: number,
  durationInFrames: number,
) => {
  const edgeInset = width * 0.018;
  const left = edgeInset;
  const center = width / 2;
  const right = width - edgeInset;
  const centerPause = Math.round(0.3 * PHOTO_ENHANCE_FPS);
  const travel = Math.round(1.25 * PHOTO_ENHANCE_FPS);
  const halfCycle = travel + centerPause + travel;
  const endPause = Math.max(0, durationInFrames - halfCycle * 2);
  const frames = [
    0,
    travel,
    travel + centerPause,
    halfCycle,
    halfCycle + travel,
    halfCycle + travel + centerPause,
    durationInFrames - endPause,
    durationInFrames,
  ];
  const positions = [left, center, center, right, center, center, left, left];

  for (let index = 0; index < frames.length - 1; index += 1) {
    if (frame <= frames[index + 1]) {
      return interpolate(
        frame,
        [frames[index], frames[index + 1]],
        [positions[index], positions[index + 1]],
        {
          easing: Easing.bezier(0.22, 1, 0.36, 1),
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        },
      );
    }
  }

  return left;
};

export const EnhancePhotoComparisonCover: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames, width, height } = useVideoConfig();
  const dividerX = interpolateSweepWithCenterPause(
    frame,
    width,
    durationInFrames,
  );

  const imageStyle: React.CSSProperties = {
    position: "absolute",
    inset: 0,
    width: "100%",
    height: "100%",
    objectFit: "cover",
  };

  return (
    <AbsoluteFill
      style={{
        width,
        height,
        backgroundColor: "#111111",
        overflow: "hidden",
      }}
    >
      <Img src={staticFile("enhance-photo-before.png")} style={imageStyle} />
      <Img
        src={staticFile("enhance-photo-after.png")}
        style={{
          ...imageStyle,
          clipPath: `inset(0 0 0 ${dividerX}px)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: dividerX - 2,
          width: 4,
          backgroundColor: "rgba(255, 255, 255, 0.98)",
          boxShadow:
            "-2px 0 5px rgba(0, 0, 0, 0.38), 2px 0 5px rgba(0, 0, 0, 0.38), 0 0 10px rgba(255, 255, 255, 0.42)",
        }}
      />
    </AbsoluteFill>
  );
};

export const EnhancePhotoComparisonComposition: React.FC = () => {
  return (
    <Composition
      id="EnhancePhotoComparisonCover"
      component={EnhancePhotoComparisonCover}
      durationInFrames={PHOTO_ENHANCE_DURATION_FRAMES}
      fps={PHOTO_ENHANCE_FPS}
      width={1536}
      height={1024}
    />
  );
};
