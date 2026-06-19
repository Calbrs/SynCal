// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scheduled_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ScheduledMessageAdapter extends TypeAdapter<ScheduledMessage> {
  @override
  final int typeId = 107;

  @override
  ScheduledMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScheduledMessage(
      id: fields[0] as String,
      message: fields[1] as String,
      scheduledTime: fields[2] as DateTime,
      repetition: fields[3] as Repetition,
      recipientIds: (fields[4] as List).cast<String>(),
      simSlot: fields[5] as int,
      simLabel: fields[6] as String,
      isActive: fields[7] as bool,
      createdAt: fields[8] as DateTime,
      sentCount: fields[9] as int?,
      status: fields[10] as ScheduleStatus,
      completedAt: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ScheduledMessage obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.message)
      ..writeByte(2)
      ..write(obj.scheduledTime)
      ..writeByte(3)
      ..write(obj.repetition)
      ..writeByte(4)
      ..write(obj.recipientIds)
      ..writeByte(5)
      ..write(obj.simSlot)
      ..writeByte(6)
      ..write(obj.simLabel)
      ..writeByte(7)
      ..write(obj.isActive)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.sentCount)
      ..writeByte(10)
      ..write(obj.status)
      ..writeByte(11)
      ..write(obj.completedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RepetitionAdapter extends TypeAdapter<Repetition> {
  @override
  final int typeId = 105;

  @override
  Repetition read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Repetition.none;
      case 1:
        return Repetition.daily;
      case 2:
        return Repetition.weekly;
      case 3:
        return Repetition.monthly;
      default:
        return Repetition.none;
    }
  }

  @override
  void write(BinaryWriter writer, Repetition obj) {
    switch (obj) {
      case Repetition.none:
        writer.writeByte(0);
        break;
      case Repetition.daily:
        writer.writeByte(1);
        break;
      case Repetition.weekly:
        writer.writeByte(2);
        break;
      case Repetition.monthly:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepetitionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ScheduleStatusAdapter extends TypeAdapter<ScheduleStatus> {
  @override
  final int typeId = 106;

  @override
  ScheduleStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ScheduleStatus.pending;
      case 1:
        return ScheduleStatus.sent;
      case 2:
        return ScheduleStatus.failed;
      default:
        return ScheduleStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, ScheduleStatus obj) {
    switch (obj) {
      case ScheduleStatus.pending:
        writer.writeByte(0);
        break;
      case ScheduleStatus.sent:
        writer.writeByte(1);
        break;
      case ScheduleStatus.failed:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
