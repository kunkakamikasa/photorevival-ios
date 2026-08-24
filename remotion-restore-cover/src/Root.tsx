import "./index.css";
import {
  EnhancePhotoComparisonComposition,
  EnhanceVideoComparisonComposition,
  RestoreCoverComposition,
} from "./Composition";
import {TextToVideoCoverComposition} from "./TextToVideoCover";
import {Composition} from "remotion";
import {GPTImageMagicCover} from "./GPTImageMagicCover";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <RestoreCoverComposition />
      <EnhanceVideoComparisonComposition />
      <EnhancePhotoComparisonComposition />
      <TextToVideoCoverComposition />
      <Composition
        id="GPTImageMagicCover"
        component={GPTImageMagicCover}
        durationInFrames={180}
        fps={30}
        width={1280}
        height={720}
      />
    </>
  );
};
