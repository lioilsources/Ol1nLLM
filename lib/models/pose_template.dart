/// Predefined OpenPose skeleton templates for ControlNet pose guidance.
///
/// The PNGs (512×768 skeletons) are bundled as assets — the same file serves
/// as the picker thumbnail and, uploaded via POST /upload/image, as the
/// ControlNet input at generation time. [PoseTemplate.id] is persisted in
/// sessions, so never rename existing ids.
class PoseTemplate {
  const PoseTemplate({
    required this.id,
    required this.label,
    required this.asset,
  });

  final String id;
  final String label;
  final String asset;
}

/// Latent dimensions used whenever a pose is active. The skeletons are 2:3
/// portrait (512×768); 832×1216 is the closest standard SDXL bucket, so the
/// pose isn't stretched into the preset's default square.
const kPoseWidth = 832;
const kPoseHeight = 1216;

const kPoseTemplates = <PoseTemplate>[
  PoseTemplate(id: 'ol1', label: 'Póza 1', asset: 'assets/poses/ol1.png'),
  PoseTemplate(id: 'ol2', label: 'Póza 2', asset: 'assets/poses/ol2.png'),
  PoseTemplate(id: 'ol3', label: 'Póza 3', asset: 'assets/poses/ol3.png'),
  PoseTemplate(id: 'ol4', label: 'Póza 4', asset: 'assets/poses/ol4.png'),
  PoseTemplate(id: 'ol5', label: 'Póza 5', asset: 'assets/poses/ol5.png'),
  PoseTemplate(id: 'ol6', label: 'Póza 6', asset: 'assets/poses/ol6.png'),
  PoseTemplate(id: 'ol7', label: 'Póza 7', asset: 'assets/poses/ol7.png'),
  PoseTemplate(id: 'ol8', label: 'Póza 8', asset: 'assets/poses/ol8.png'),
];

/// Lookup by persisted id; unknown or null ids resolve to null so sessions
/// written by future builds degrade to "no pose".
PoseTemplate? poseById(String? id) {
  if (id == null) return null;
  for (final p in kPoseTemplates) {
    if (p.id == id) return p;
  }
  return null;
}
