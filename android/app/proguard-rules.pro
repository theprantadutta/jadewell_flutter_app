# R8 rules for release builds.

# WorkManager (pulled in by the Google Mobile Ads SDK) uses an old Room
# (2.2.x) that creates its generated `WorkDatabase_Impl` by reflection. R8 full
# mode (AGP 8 default) keeps the class name but strips the no-arg constructor,
# which crashed release builds at startup in androidx.startup:
#   "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
