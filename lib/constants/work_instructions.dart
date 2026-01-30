import '../models/work_instruction.dart';

class WorkInstructionsConstants {
  static const wiPellet = WorkInstruction(
    id: 'WI-PRD-28',
    title: 'Pellet Manufacturing',
    description: 'WI-PRD-28',
    videoPath: 'file:///storage/emulated/0/videos/pellet_manufacturing.mp4',
  );

  static const wiDrying = WorkInstruction(
    id: 'WI-PRD-01',
    title: 'Drying of Components',
    description: 'WI-PRD-01',
    videoPath: 'file:///storage/emulated/0/videos/drying_of_components.mp4',
  );

  static const wiAssembly = WorkInstruction(
    id: 'WI-PRD-13',
    title: 'Stack Assembly',
    description: 'WI-PRD-13',
    videoPath: 'file:///storage/emulated/0/videos/stack_assembly.mp4',
  );

  static const wiPowder = WorkInstruction(
    id: 'WI-PRD-30',
    title: 'Preparation of EB',
    description: 'WI-PRD-30',
    videoPath: 'file:///storage/emulated/0/videos/preparation_of_eb.mp4',
  );

  static const List<WorkInstruction> allWis = [
    wiPellet,
    wiDrying,
    wiAssembly,
    wiPowder,
  ];
}
