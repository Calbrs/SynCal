// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sms_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SmsRecipientAdapter extends TypeAdapter<SmsRecipient> {
  @override
  final int typeId = 102;

  @override
  SmsRecipient read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SmsRecipient(
      name: fields[0] as String,
      phone: fields[1] as String,
      status: fields[2] as SmsRecipientStatus,
      error: fields[3] as String?,
      msgId: fields[4] as String?,
      retryCount: fields[5] as int,
      deliveryRetryCount: fields[6] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, SmsRecipient obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.phone)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.error)
      ..writeByte(4)
      ..write(obj.msgId)
      ..writeByte(5)
      ..write(obj.retryCount)
      ..writeByte(6)
      ..write(obj.deliveryRetryCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsRecipientAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SmsSessionAdapter extends TypeAdapter<SmsSession> {
  @override
  final int typeId = 104;

  @override
  SmsSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SmsSession(
      id: fields[0] as String,
      message: fields[1] as String,
      startedAt: fields[2] as DateTime,
      simSlot: fields[3] as int,
      simLabel: fields[4] as String,
      recipients: (fields[5] as List).cast<SmsRecipient>(),
      state: fields[6] as SmsSessionState,
      retryPass: fields[7] as int,
      finishedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, SmsSession obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.message)
      ..writeByte(2)
      ..write(obj.startedAt)
      ..writeByte(3)
      ..write(obj.simSlot)
      ..writeByte(4)
      ..write(obj.simLabel)
      ..writeByte(5)
      ..write(obj.recipients)
      ..writeByte(6)
      ..write(obj.state)
      ..writeByte(7)
      ..write(obj.retryPass)
      ..writeByte(8)
      ..write(obj.finishedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SmsRecipientStatusAdapter extends TypeAdapter<SmsRecipientStatus> {
  @override
  final int typeId = 101;

  @override
  SmsRecipientStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SmsRecipientStatus.pending;
      case 1:
        return SmsRecipientStatus.sent;
      case 2:
        return SmsRecipientStatus.failed;
      case 3:
        return SmsRecipientStatus.sentNotDelivered;
      default:
        return SmsRecipientStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, SmsRecipientStatus obj) {
    switch (obj) {
      case SmsRecipientStatus.pending:
        writer.writeByte(0);
        break;
      case SmsRecipientStatus.sent:
        writer.writeByte(1);
        break;
      case SmsRecipientStatus.failed:
        writer.writeByte(2);
        break;
      case SmsRecipientStatus.sentNotDelivered:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsRecipientStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SmsSessionStateAdapter extends TypeAdapter<SmsSessionState> {
  @override
  final int typeId = 103;

  @override
  SmsSessionState read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SmsSessionState.running;
      case 1:
        return SmsSessionState.retrying;
      case 2:
        return SmsSessionState.done;
      default:
        return SmsSessionState.running;
    }
  }

  @override
  void write(BinaryWriter writer, SmsSessionState obj) {
    switch (obj) {
      case SmsSessionState.running:
        writer.writeByte(0);
        break;
      case SmsSessionState.retrying:
        writer.writeByte(1);
        break;
      case SmsSessionState.done:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsSessionStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
