/* ================================================================
   FitPro — application logic
   Sections:
     1  state + escaping
     2  storage (profile-namespaced) + migrations
     3  translations
     4  language
     5  profiles
     6  macros + onboarding
     7  navigation
     8  dashboard
     9  daily metrics (per-date history)
    10  program: exercises + templates + day picker
    11  live workout: per-set logging, last-time, PR, rest timer
    12  training log
    13  history: weekly/monthly + charts + volume
    14  nutrition
    15  machine vision
    16  plate calculator
    17  export / import
    18  boot
   ================================================================ */

/* ---------- 1. state ---------- */
let user = null;
let metrics = null;
let meals = [];
let exercises = [];
let trainingLog = [];
let dailyLog = {};            // { 'YYYY-MM-DD': { sleep, steps, bodyKg, restHr } }
let templates = [];
let settings = { defaultRestSec: 90, barKg: 20 };
let trainingDays = [false, false, false, false, false, false, false];

let profiles = [];
let activeProfileId = null;

let editingMealIndex = null;
let editingExerciseIndex = null;
let editingLogId = null;
let editingTemplateId = null;
let viewingDate = null;       // dashboard metrics day being viewed

/* Free text the user typed goes back out through innerHTML — always escape. */
function esc(v){
  return String(v == null ? '' : v).replace(/[&<>"']/g, function(c){
    return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c];
  });
}
function num(v, d){ const n = Number(v); return Number.isFinite(n) ? n : (d || 0); }

/* Whole number >= 1; blank, zero or negative falls back to `dflt`. */
function posInt(v, dflt){
  const n = Math.round(num(v));
  return n >= 1 ? n : dflt;
}

const MEAL_TAG_EMOJI = { breakfast:'\u{1F373}', lunch:'\u{1F37D}\u{FE0F}', dinner:'\u{1F319}', snack:'\u{1F34E}' };
const MUSCLES = ['chest','back','legs','shoulders','arms','core','cardio','other'];
const MUSCLE_KEY = { chest:'muscleChest', back:'muscleBack', legs:'muscleLegs', shoulders:'muscleShoulders',
                     arms:'muscleArms', core:'muscleCore', cardio:'muscleCardio', other:'muscleOther' };
/* Evidence-based weekly set range per muscle group used by the volume view. */
const VOL_MIN = 10, VOL_MAX = 20;

/* ---------- 2. storage ---------- */
function K(key){ return activeProfileId ? 'fitpro:p:' + activeProfileId + ':' + key : 'fitpro:' + key; }

function saveKey(key, value){
  try { localStorage.setItem(K(key), JSON.stringify(value)); }
  catch(e){ console.warn('storage save failed', e); }
}
function loadKey(key, fallback){
  try {
    const raw = localStorage.getItem(K(key));
    if(raw !== null) return JSON.parse(raw);
  } catch(e){ /* absent or storage unavailable (private browsing) */ }
  return fallback;
}
function saveGlobal(key, value){
  try { localStorage.setItem('fitpro:' + key, JSON.stringify(value)); } catch(e){}
}
function loadGlobal(key, fallback){
  try {
    const raw = localStorage.getItem('fitpro:' + key);
    if(raw !== null) return JSON.parse(raw);
  } catch(e){}
  return fallback;
}

function dayKey(d){
  const x = d instanceof Date ? d : new Date(d);
  return x.getFullYear() + '-' + String(x.getMonth()+1).padStart(2,'0') + '-' + String(x.getDate()).padStart(2,'0');
}
function todayKey(){ return dayKey(new Date()); }

/* Move a pre-profile install into profile storage, then upgrade the shapes.
   Runs once; every step checks before it writes so re-running is harmless. */
function migrateToProfiles(){
  profiles = loadGlobal('profiles', []);
  activeProfileId = loadGlobal('activeProfile', null);

  const legacyUser = loadGlobal('user', null);
  if(profiles.length === 0 && legacyUser){
    const id = 'p' + Date.now();
    profiles = [{ id, name: legacyUser.name || 'Me', createdAt: new Date().toISOString() }];
    activeProfileId = id;
    saveGlobal('profiles', profiles);
    saveGlobal('activeProfile', id);
    ['user','metrics','meals','exercises','trainingLog','dailyStats','trainingDays','workout'].forEach(function(k){
      const raw = localStorage.getItem('fitpro:' + k);
      if(raw !== null && localStorage.getItem('fitpro:p:' + id + ':' + k) === null){
        try { localStorage.setItem('fitpro:p:' + id + ':' + k, raw); } catch(e){}
      }
    });
  }
  if(profiles.length && !activeProfileId){
    activeProfileId = profiles[0].id;
    saveGlobal('activeProfile', activeProfileId);
  }
}

/* dailyStats was a single object with no date, so every day overwrote the one
   before it. Keep whatever value was there by filing it under today. */
function migrateDailyLog(){
  dailyLog = loadKey('dailyLog', null);
  if(dailyLog) return;
  dailyLog = {};
  const old = loadKey('dailyStats', null);
  if(old && (num(old.sleep) > 0 || num(old.steps) > 0)){
    dailyLog[todayKey()] = { sleep: num(old.sleep), steps: num(old.steps), bodyKg: 0, restHr: 0 };
  }
  saveKey('dailyLog', dailyLog);
}

/* Exercises gained muscle group / target weight / rest. Log entries gained
   real per-set data; old entries only ever stored a list of names. */
function migrateShapes(){
  let exDirty = false;
  exercises.forEach(function(ex){
    if(!ex.id){ ex.id = 'e' + Math.random().toString(36).slice(2,9); exDirty = true; }
    if(!ex.muscle){ ex.muscle = 'other'; exDirty = true; }
    if(ex.targetKg === undefined){ ex.targetKg = 0; exDirty = true; }
    if(ex.restSec === undefined){ ex.restSec = settings.defaultRestSec; exDirty = true; }
  });
  if(exDirty) saveKey('exercises', exercises);

  let logDirty = false;
  trainingLog.forEach(function(en){
    if(!en.entries){
      en.entries = (en.exerciseNames || []).map(function(n){
        return { name: n, muscle: 'other', sets: [] };
      });
      en.legacy = true;
      logDirty = true;
    }
  });
  if(logDirty) saveKey('trainingLog', trainingLog);
}

/* ---------- 3. translations ---------- */
const translations = {
  he: {
    onboardSubtitle: 'בואו נתחיל את הטיול שלך לכושר',
    fieldName: 'שם פרטי', placeholderName: 'לדוגמה: דניאל', errorName: 'נא להזין שם',
    fieldAge: 'גיל', errorAge: 'נא להזין גיל בין 13 ל-120',
    fieldGender: 'מין', genderMale: 'זכר', genderFemale: 'נקבה',
    fieldWeight: 'משקל (ק״ג)', errorWeight: 'נא להזין משקל בין 20 ל-300 ק״ג',
    fieldHeight: 'גובה (ס״מ)', errorHeight: 'נא להזין גובה בין 100 ל-250 ס״מ',
    fieldGoal: 'מה היעד שלך?', goalPlaceholder: 'בחר יעד...',
    goalWeightLoss: '🔥 חיטוב (הפחתת משקל)', goalMaintenance: '⚖️ שמירה על משקל', goalMuscleGain: '💪 בנייה שרירית',
    errorGoal: 'נא לבחור יעד',
    macroTitle: '🎯 התוכנית התזונתית שלך', macroCals: 'קלוריות', macroProtein: 'חלבון', macroCarbs: 'פחמימות', macroFats: 'שומן',
    unitKcalDay: 'kcal/יום', unitGramDay: 'גרם/יום',
    macroTip: '<strong>💡 טיפ:</strong> הנתונים האלו מחושבים בהתאם לפרופיל שלך. אתה יכול לשנות אותם בכל עת.',
    submitBtn: 'התחל עכשיו',
    brandSubtitle: 'מאמן אישי',
    navDashboard: 'לוח בקרה', navLive: 'אימון חי', navProgram: 'תוכנית אימונים',
    navHistory: 'היסטוריה', navProgress: 'התקדמות', navNutrition: 'תזונה ומדדים',
    startWorkoutBtn: 'התחל אימון',
    greetingDefault: 'שלום 👋',
    heroTrainingDay: 'יום אימון', heroRestDay: 'יום מנוחה',
    heroNoProgram: 'עדיין לא בנית תוכנית אימונים', heroProgramReady: 'התוכנית שלך מוכנה',
    heroMetaNoProgram: 'הוסיפו תרגילים במסך תוכנית האימונים',
    heroExercisesLabel: 'תרגילים', heroTodayLogged: 'אימונים היום', heroMinutesLabel: 'דקות', heroCalLabel: 'קק״ל',
    editPlanBtn: 'ערוך תוכנית', startNowBtn: 'התחל עכשיו ▶',
    nutritionGoalTitle: '🎯 היעד התזונתי שלך היום',
    sleepTitle: 'שעות שינה', sleepUnit: 'שעות', stepsTitle: 'צעדים', weeklyProgressTitle: 'התקדמות שבועית',
    bodyWeightTitle: 'משקל גוף', restHrTitle: 'דופק מנוחה', kgUnit: 'ק״ג', bpmUnit: 'פעימות',
    dayMetricsTitle: 'מדדים יומיים', todayLabel: 'היום', yesterdayLabel: 'אתמול',
    metricsSavedToast: 'המדד נשמר',
    bodyWeightSyncedToast: 'משקל הגוף עודכן והיעדים חושבו מחדש',
    liveTitle: 'אימון פעיל',
    workoutTimerTitle: 'טיימר אימון', notStartedLabel: 'האימון טרם התחיל', inProgressLabel: 'האימון בעיצומו…', pausedLabel: 'האימון מושהה',
    startWorkoutCta: 'התחל אימון ▶', resumeBtn: 'המשך ▶', pauseBtn: 'השהה ⏸', finishWorkoutBtn: 'סיים ותעד ✓',
    logNamePlaceholder: 'שם האימון (לדוגמה: רגליים)', logExercisesLabel: 'תרגילים שבוצעו',
    noExercisesYet: 'עדיין לא הוספת תרגילים בתוכנית האימונים',
    logCaloriesPlaceholder: 'קלוריות (אופציונלי)', logNotesPlaceholder: 'הערות (אופציונלי)', logSaveBtn: 'שמור אימון ביומן',
    logNameDefault: 'אימון', trainingLogTitle: 'יומן אימונים',
    logEmptyState: 'עדיין לא תיעדת אימונים. סיים אימון כדי להוסיף רשומה ראשונה!',
    logSavedToast: 'האימון נשמר ביומן!', minUnit: 'דק׳',
    notificationsToast: 'אין התראות חדשות', searchComingSoon: 'החיפוש יגיע בקרוב',
    liveInfoToast: 'לחצו "התחל אימון" כדי לתעד סטים, משקלים וזמן מנוחה',
    programTitle: 'תוכנית אימונים', weeklyPlanTitle: 'תוכנית שבועית',
    weeklyPlanHint: 'לחצו על יום כדי לסמן אותו כיום אימון', exercisesTitle: 'תרגילים',
    exNamePlaceholder: 'שם התרגיל', exTagPlaceholder: 'תגית (אופציונלי)',
    exSetsPlaceholder: 'סטים', exRepsPlaceholder: 'חזרות', exKgPlaceholder: 'משקל (ק״ג)', exRestPlaceholder: 'מנוחה (שנ׳)',
    exMuscleLabel: 'קבוצת שריר',
    saveExerciseBtn: 'שמור תרגיל', cancelBtn: 'ביטול', addExerciseBtn: '＋ הוסף תרגיל', setsUnit: 'סטים', generalTag: 'כללי',
    metricsTitle: 'מדדים אישיים', metricAgeLabel: 'גיל', metricHeightLabel: 'גובה (ס״מ)', metricWeightLabel: 'משקל (ק״ג)',
    updateMetricsBtn: 'עדכן מדדים',
    mealNamePlaceholder: 'שם הארוחה',
    mealTagBreakfast: 'ארוחת בוקר', mealTagLunch: 'ארוחת צהריים', mealTagDinner: 'ארוחת ערב', mealTagSnack: 'חטיף',
    mealCalPlaceholder: 'קלוריות', mealProteinPlaceholder: "חלבון (ג')", mealCarbsPlaceholder: "פחמימות (ג')",
    saveMealBtn: 'שמור ארוחה', addMealBtn: '＋ הוסף ארוחה', dailySummaryTitle: 'סיכום יומי',
    calUnitShort: 'קק"ל', calUnitLabel: 'קק״ל', gramUnit: 'ג׳',
    savedToastDefault: 'נשמר',
    mealSavedToast: 'הארוחה נוספה ונשמרה', mealNameAlert: 'נא להזין שם ארוחה',
    exerciseSavedToast: 'התרגיל נוסף ונשמר', exerciseNameAlert: 'נא להזין שם תרגיל',
    metricsUpdatedToast: 'המדדים עודכנו ויעדים חושבו מחדש',
    editAction: 'עריכה', deleteAction: 'מחיקה', saveChangesBtn: 'שמור שינויים',
    mealUpdatedToast: 'הארוחה עודכנה', mealDeletedToast: 'הארוחה נמחקה',
    exerciseUpdatedToast: 'התרגיל עודכן', exerciseDeletedToast: 'התרגיל נמחק',
    logUpdatedToast: 'האימון עודכן', logDeletedToast: 'האימון נמחק', workoutRestoredToast: 'האימון שוחזר ומושהה',
    langToggle: 'EN',
    monthNames: ['ינואר','פברואר','מרץ','אפריל','מאי','יוני','יולי','אוגוסט','ספטמבר','אוקטובר','נובמבר','דצמבר'],
    dayNamesShort: ['א׳','ב׳','ג׳','ד׳','ה׳','ו׳','ש׳'],
    mealsEmptyState: 'עדיין לא הוספת ארוחות היום', exercisesEmptyState: 'עדיין לא הוספת תרגילים לתוכנית',
    historyTitle: 'היסטוריית אימונים', weeklyStats: 'סיכום שבועי', monthlyTrends: 'סיכום חודשי',
    totalStatsTitle: 'סך הכל', noHistoryYet: 'אין היסטוריה עדיין. סיימו אימון כדי להתחיל לעקוב.',
    workoutsUnit: 'אימונים', volumeUnit: 'טונאז׳',
    /* per-set logging */
    setColSet: 'סט', setColKg: 'ק״ג', setColReps: 'חזרות', setColDone: 'בוצע',
    addSetBtn: '＋ הוסף סט', lastTimeLabel: 'בפעם הקודמת:', noLastTime: 'אימון ראשון בתרגיל הזה',
    sessionEmpty: 'לא נבחרו תרגילים. הוסיפו תרגילים לאימון כדי לתעד סטים.',
    addToSessionBtn: '＋ הוסף תרגיל לאימון', sessionTitle: 'תרגילי האימון',
    prToast: '🏆 שיא חדש!', e1rmLabel: '1RM משוער',
    /* rest timer */
    restLabel: 'מנוחה', restSkip: 'דלג', restPlus: '+30 שנ׳', restDoneToast: 'המנוחה הסתיימה — לסט הבא!',
    /* templates */
    templatesTitle: 'תבניות אימון', templateNamePlaceholder: 'שם התבנית (לדוגמה: דחיפה)',
    saveTemplateBtn: 'שמור תבנית', addTemplateBtn: '＋ תבנית חדשה',
    templatesEmpty: 'אין תבניות. צרו תבנית כדי להתחיל אימון בלחיצה אחת.',
    startFromTemplate: 'התחל', templateSavedToast: 'התבנית נשמרה', templateDeletedToast: 'התבנית נמחקה',
    templateNameAlert: 'נא להזין שם תבנית', templateExAlert: 'נא לבחור לפחות תרגיל אחד',
    templateStartedToast: 'האימון התחיל מתבנית',
    /* progress */
    progressTitle: 'התקדמות', pickExercise: 'בחרו תרגיל', volumeTitle: 'נפח שבועי לפי קבוצת שריר',
    volumeHint: 'סטים בשבוע האחרון. הטווח המומלץ הוא 10–20 סטים לקבוצה.',
    bodyWeightChartTitle: 'מגמת משקל גוף', strengthChartTitle: 'התקדמות בתרגיל (1RM משוער)',
    noChartData: 'אין מספיק נתונים להצגת גרף. תעדו עוד אימונים.',
    setsUnitShort: 'סטים',
    /* muscles */
    muscleChest: 'חזה', muscleBack: 'גב', muscleLegs: 'רגליים', muscleShoulders: 'כתפיים',
    muscleArms: 'ידיים', muscleCore: 'ליבה', muscleCardio: 'אירובי', muscleOther: 'אחר',
    /* vision */
    captureImage: '📷 צלם מכשיר', cameraTitle: 'זיהוי מכשיר', cameraStart: 'הפעל מצלמה',
    cameraShoot: '📸 צלם', cameraRetake: 'צלם שוב', cameraAnalyze: 'נתח תמונה',
    cameraAnalyzing: 'מנתח…', cameraNoAccess: 'אין גישה למצלמה',
    cameraHint: 'כוונו את המצלמה למכשיר וצלמו',
    visionNotConfigured: 'זיהוי המכשירים אינו מוגדר בשרת. צריך להוסיף ANTHROPIC_API_KEY ל-Vercel כדי להפעיל את הפיצ׳ר. עד אז אפשר להוסיף את התרגיל ידנית.',
    visionFailed: 'הניתוח נכשל. נסו שוב או הוסיפו את התרגיל ידנית.',
    visionAddBtn: '＋ הוסף לתוכנית',
    /* vision: food */
    captureFood: '📷 צלם אוכל', cameraTitleFood: 'זיהוי ארוחה',
    cameraHintFood: 'כוונו את המצלמה לצלחת וצלמו',
    visionNotConfiguredFood: 'זיהוי המזון אינו מוגדר בשרת. צריך להוסיף ANTHROPIC_API_KEY ל-Vercel כדי להפעיל את הפיצ׳ר. עד אז אפשר להוסיף את הארוחה ידנית.',
    visionFailedFood: 'הניתוח נכשל. נסו שוב או הוסיפו את הארוחה ידנית.',
    visionUseBtn: '✓ מלא בטופס',
    mealFilledFromPhotoToast: 'הנתונים מולאו מהתמונה — בדקו ושמרו',
    /* profiles */
    profilesTitle: 'פרופילים', profileSwitchBtn: '👤 החלף פרופיל', newProfileBtn: '＋ פרופיל חדש',
    profileNamePlaceholder: 'שם הפרופיל', profileCreatedToast: 'הפרופיל נוצר',
    profileSwitchedToast: 'הפרופיל הוחלף', profileDeleteConfirm: 'למחוק את הפרופיל וכל הנתונים שלו?',
    profileDeletedToast: 'הפרופיל נמחק', profileNameAlert: 'נא להזין שם פרופיל',
    profileLocalNote: 'הפרופילים נשמרים במכשיר הזה בלבד. אין סנכרון בין מכשירים.',
    workoutsCount: 'אימונים',
    /* plate calculator */
    plateTitle: 'מחשבון פלטות', plateTarget: 'משקל יעד (ק״ג)', plateBar: 'משקל המוט (ק״ג)',
    plateResult: 'לכל צד', plateImpossible: 'לא ניתן להרכיב בדיוק את המשקל הזה',
    plateCalcBtn: '🏋 מחשבון פלטות',
    /* export */
    dataTitle: 'הנתונים שלי', exportBtn: '⬇ ייצוא גיבוי', importBtn: '⬆ ייבוא גיבוי',
    exportedToast: 'הגיבוי הורד', importedToast: 'הנתונים יובאו',
    importFailed: 'קובץ הגיבוי לא תקין', importConfirm: 'הייבוא ידרוס את כל הנתונים בפרופיל הזה. להמשיך?',
    dataNote: 'הנתונים נשמרים בדפדפן בלבד. ניקוי הדפדפן ימחק אותם — כדאי לייצא גיבוי מדי פעם.',
    greeting: (name) => `שלום, ${name} 👋`,
    welcomeToast: (name) => `ברוכים הבאים, ${name}!`
  },
  en: {
    onboardSubtitle: "Let's start your fitness journey",
    fieldName: 'First name', placeholderName: 'e.g. Daniel', errorName: 'Please enter your name',
    fieldAge: 'Age', errorAge: 'Please enter an age between 13 and 120',
    fieldGender: 'Gender', genderMale: 'Male', genderFemale: 'Female',
    fieldWeight: 'Weight (kg)', errorWeight: 'Please enter a weight between 20 and 300 kg',
    fieldHeight: 'Height (cm)', errorHeight: 'Please enter a height between 100 and 250 cm',
    fieldGoal: 'What is your goal?', goalPlaceholder: 'Choose a goal...',
    goalWeightLoss: '🔥 Cutting (weight loss)', goalMaintenance: '⚖️ Maintain weight', goalMuscleGain: '💪 Build muscle',
    errorGoal: 'Please choose a goal',
    macroTitle: '🎯 Your nutrition plan', macroCals: 'Calories', macroProtein: 'Protein', macroCarbs: 'Carbs', macroFats: 'Fat',
    unitKcalDay: 'kcal/day', unitGramDay: 'g/day',
    macroTip: '<strong>💡 Tip:</strong> these numbers are calculated from your profile. You can change them anytime.',
    submitBtn: 'Get Started',
    brandSubtitle: 'Personal trainer',
    navDashboard: 'Dashboard', navLive: 'Live Workout', navProgram: 'Training Program',
    navHistory: 'History', navProgress: 'Progress', navNutrition: 'Nutrition & Metrics',
    startWorkoutBtn: 'Start Workout',
    greetingDefault: 'Hi 👋',
    heroTrainingDay: 'Training day', heroRestDay: 'Rest day',
    heroNoProgram: "You haven't built a training program yet", heroProgramReady: 'Your program is ready',
    heroMetaNoProgram: 'Add exercises on the Training Program screen',
    heroExercisesLabel: 'Exercises', heroTodayLogged: 'logged today', heroMinutesLabel: 'Minutes', heroCalLabel: 'kcal',
    editPlanBtn: 'Edit plan', startNowBtn: 'Start Now ▶',
    nutritionGoalTitle: "🎯 Today's Nutrition Goal",
    sleepTitle: 'Sleep', sleepUnit: 'hrs', stepsTitle: 'Steps', weeklyProgressTitle: 'Weekly Progress',
    bodyWeightTitle: 'Body weight', restHrTitle: 'Resting HR', kgUnit: 'kg', bpmUnit: 'bpm',
    dayMetricsTitle: 'Daily metrics', todayLabel: 'Today', yesterdayLabel: 'Yesterday',
    metricsSavedToast: 'Saved',
    bodyWeightSyncedToast: 'Body weight updated — goals recalculated',
    liveTitle: 'Active Workout',
    workoutTimerTitle: 'Workout Timer', notStartedLabel: 'Workout not started', inProgressLabel: 'Workout in progress…', pausedLabel: 'Workout paused',
    startWorkoutCta: 'Start Workout ▶', resumeBtn: 'Resume ▶', pauseBtn: 'Pause ⏸', finishWorkoutBtn: 'Finish & Log ✓',
    logNamePlaceholder: 'Workout name (e.g. Leg Day)', logExercisesLabel: 'Exercises performed',
    noExercisesYet: "You haven't added exercises to your program yet",
    logCaloriesPlaceholder: 'Calories (optional)', logNotesPlaceholder: 'Notes (optional)', logSaveBtn: 'Save to training log',
    logNameDefault: 'Workout', trainingLogTitle: 'Training Log',
    logEmptyState: 'No workouts logged yet. Finish a workout to add your first entry!',
    logSavedToast: 'Workout saved to your training log!', minUnit: 'min',
    notificationsToast: 'No new notifications', searchComingSoon: 'Search coming soon',
    liveInfoToast: 'Tap "Start Workout" to log sets, weights and rest',
    programTitle: 'Training Program', weeklyPlanTitle: 'Weekly Plan',
    weeklyPlanHint: 'Tap a day to mark it as a training day', exercisesTitle: 'Exercises',
    exNamePlaceholder: 'Exercise name', exTagPlaceholder: 'Tag (optional)',
    exSetsPlaceholder: 'Sets', exRepsPlaceholder: 'Reps', exKgPlaceholder: 'Weight (kg)', exRestPlaceholder: 'Rest (sec)',
    exMuscleLabel: 'Muscle group',
    saveExerciseBtn: 'Save exercise', cancelBtn: 'Cancel', addExerciseBtn: '＋ Add exercise', setsUnit: 'sets', generalTag: 'General',
    metricsTitle: 'Personal Metrics', metricAgeLabel: 'Age', metricHeightLabel: 'Height (cm)', metricWeightLabel: 'Weight (kg)',
    updateMetricsBtn: 'Update metrics',
    mealNamePlaceholder: 'Meal name',
    mealTagBreakfast: 'Breakfast', mealTagLunch: 'Lunch', mealTagDinner: 'Dinner', mealTagSnack: 'Snack',
    mealCalPlaceholder: 'Calories', mealProteinPlaceholder: 'Protein (g)', mealCarbsPlaceholder: 'Carbs (g)',
    saveMealBtn: 'Save meal', addMealBtn: '＋ Add meal', dailySummaryTitle: 'Daily Summary',
    calUnitShort: 'kcal', calUnitLabel: 'kcal', gramUnit: 'g',
    savedToastDefault: 'Saved',
    mealSavedToast: 'Meal added and saved', mealNameAlert: 'Please enter a meal name',
    exerciseSavedToast: 'Exercise added and saved', exerciseNameAlert: 'Please enter an exercise name',
    metricsUpdatedToast: 'Metrics updated and goals recalculated',
    editAction: 'Edit', deleteAction: 'Delete', saveChangesBtn: 'Save changes',
    mealUpdatedToast: 'Meal updated', mealDeletedToast: 'Meal deleted',
    exerciseUpdatedToast: 'Exercise updated', exerciseDeletedToast: 'Exercise deleted',
    logUpdatedToast: 'Workout updated', logDeletedToast: 'Workout deleted', workoutRestoredToast: 'Workout restored (paused)',
    langToggle: 'עב',
    monthNames: ['January','February','March','April','May','June','July','August','September','October','November','December'],
    dayNamesShort: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'],
    mealsEmptyState: "You haven't added any meals yet today", exercisesEmptyState: "You haven't added exercises to your program yet",
    historyTitle: 'Workout History', weeklyStats: 'Weekly summary', monthlyTrends: 'Monthly summary',
    totalStatsTitle: 'All time', noHistoryYet: 'No history yet. Finish a workout to start tracking.',
    workoutsUnit: 'workouts', volumeUnit: 'tonnage',
    setColSet: 'Set', setColKg: 'kg', setColReps: 'reps', setColDone: 'Done',
    addSetBtn: '＋ Add set', lastTimeLabel: 'Last time:', noLastTime: 'First time doing this exercise',
    sessionEmpty: 'No exercises picked. Add exercises to this workout to log sets.',
    addToSessionBtn: '＋ Add exercise to workout', sessionTitle: 'Workout exercises',
    prToast: '🏆 New PR!', e1rmLabel: 'Est. 1RM',
    restLabel: 'Rest', restSkip: 'Skip', restPlus: '+30s', restDoneToast: 'Rest over — next set!',
    templatesTitle: 'Workout templates', templateNamePlaceholder: 'Template name (e.g. Push)',
    saveTemplateBtn: 'Save template', addTemplateBtn: '＋ New template',
    templatesEmpty: 'No templates yet. Create one to start a workout in a single tap.',
    startFromTemplate: 'Start', templateSavedToast: 'Template saved', templateDeletedToast: 'Template deleted',
    templateNameAlert: 'Please enter a template name', templateExAlert: 'Pick at least one exercise',
    templateStartedToast: 'Workout started from template',
    progressTitle: 'Progress', pickExercise: 'Pick an exercise', volumeTitle: 'Weekly volume by muscle group',
    volumeHint: 'Sets in the last 7 days. The recommended range is 10–20 sets per group.',
    bodyWeightChartTitle: 'Body weight trend', strengthChartTitle: 'Exercise progress (est. 1RM)',
    noChartData: 'Not enough data to draw a chart yet. Log a few more workouts.',
    setsUnitShort: 'sets',
    muscleChest: 'Chest', muscleBack: 'Back', muscleLegs: 'Legs', muscleShoulders: 'Shoulders',
    muscleArms: 'Arms', muscleCore: 'Core', muscleCardio: 'Cardio', muscleOther: 'Other',
    captureImage: '📷 Capture machine', cameraTitle: 'Machine recognition', cameraStart: 'Start camera',
    cameraShoot: '📸 Capture', cameraRetake: 'Retake', cameraAnalyze: 'Analyze photo',
    cameraAnalyzing: 'Analyzing…', cameraNoAccess: 'No camera access',
    cameraHint: 'Point the camera at the machine and capture',
    visionNotConfigured: 'Machine recognition is not configured on the server. Add ANTHROPIC_API_KEY in Vercel to enable it. Until then you can add the exercise manually.',
    visionFailed: 'Analysis failed. Try again or add the exercise manually.',
    visionAddBtn: '＋ Add to program',
    captureFood: '📷 Capture food', cameraTitleFood: 'Food recognition',
    cameraHintFood: 'Point the camera at your plate and capture',
    visionNotConfiguredFood: 'Food recognition is not configured on the server. Add ANTHROPIC_API_KEY in Vercel to enable it. Until then you can add the meal manually.',
    visionFailedFood: 'Analysis failed. Try again or add the meal manually.',
    visionUseBtn: '✓ Fill in the form',
    mealFilledFromPhotoToast: 'Filled in from the photo — review and save',
    profilesTitle: 'Profiles', profileSwitchBtn: '👤 Switch profile', newProfileBtn: '＋ New profile',
    profileNamePlaceholder: 'Profile name', profileCreatedToast: 'Profile created',
    profileSwitchedToast: 'Profile switched', profileDeleteConfirm: 'Delete this profile and all its data?',
    profileDeletedToast: 'Profile deleted', profileNameAlert: 'Please enter a profile name',
    profileLocalNote: 'Profiles are stored on this device only. There is no cross-device sync.',
    workoutsCount: 'workouts',
    plateTitle: 'Plate calculator', plateTarget: 'Target weight (kg)', plateBar: 'Bar weight (kg)',
    plateResult: 'Per side', plateImpossible: 'That exact weight cannot be loaded',
    plateCalcBtn: '🏋 Plate calculator',
    dataTitle: 'My data', exportBtn: '⬇ Export backup', importBtn: '⬆ Import backup',
    exportedToast: 'Backup downloaded', importedToast: 'Data imported',
    importFailed: 'That backup file is not valid', importConfirm: 'Importing overwrites everything in this profile. Continue?',
    dataNote: 'Data lives in this browser only. Clearing the browser erases it — export a backup now and then.',
    greeting: (name) => `Hi, ${name} 👋`,
    welcomeToast: (name) => `Welcome, ${name}!`
  }
};

const MEAL_TAG_KEYS = { breakfast:'mealTagBreakfast', lunch:'mealTagLunch', dinner:'mealTagDinner', snack:'mealTagSnack' };
const GOAL_KEY_MAP = { 'weight-loss':'goalWeightLoss', 'maintenance':'goalMaintenance', 'muscle-gain':'goalMuscleGain' };

let currentLang = 'he';
function t(key){
  const v = translations[currentLang][key];
  return v === undefined ? key : v;
}
function goalLabel(goal){ return t(GOAL_KEY_MAP[goal]) || ''; }
function displayMealName(m){ return m.nameKey ? t(m.nameKey) : m.name; }
function displayMealTag(m){ return MEAL_TAG_KEYS[m.tag] ? t(MEAL_TAG_KEYS[m.tag]) : m.tag; }
function displayExerciseName(ex){ return ex.nameKey ? t(ex.nameKey) : ex.name; }
function muscleLabel(m){ return t(MUSCLE_KEY[m] || 'muscleOther'); }

/* ---------- 4. language ---------- */
function applyLanguage(lang){
  currentLang = lang;
  document.documentElement.lang = lang;
  document.documentElement.dir = lang === 'he' ? 'rtl' : 'ltr';

  document.querySelectorAll('[data-i18n]').forEach(function(el){
    const val = t(el.getAttribute('data-i18n'));
    if(typeof val === 'string') el.textContent = val;
  });
  document.querySelectorAll('[data-i18n-html]').forEach(function(el){
    const val = t(el.getAttribute('data-i18n-html'));
    if(typeof val === 'string') el.innerHTML = val;
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(function(el){
    const val = t(el.getAttribute('data-i18n-placeholder'));
    if(typeof val === 'string') el.placeholder = val;
  });

  saveGlobal('lang', lang);

  calcMacros();
  if(metrics){ renderDashboardGoal(); renderNutritionSummary(); }
  renderMeals();
  renderExercises();
  renderMuscleOptions();
  renderTemplates();
  renderTrainingLog();
  renderWeeklyChart();
  renderDayPicker();
  renderHero();
  renderDayMetrics();
  renderSession();
  renderHistoryStats();
  renderProgress();
  updateWorkoutButtons();
  updateRestUI();
  updateFormLabels();
  refreshCameraModalText();
  const g = document.getElementById('greetingText');
  if(g) g.textContent = user ? translations[currentLang].greeting(user.name) : t('greetingDefault');
}
function toggleLanguage(){ applyLanguage(currentLang === 'he' ? 'en' : 'he'); }

function updateFormLabels(){
  const mb = document.getElementById('mealSaveBtn');
  if(mb) mb.textContent = editingMealIndex === null ? t('saveMealBtn') : t('saveChangesBtn');
  const eb = document.getElementById('exSaveBtn');
  if(eb) eb.textContent = editingExerciseIndex === null ? t('saveExerciseBtn') : t('saveChangesBtn');
  const lb = document.getElementById('logSaveBtnEl');
  if(lb) lb.textContent = editingLogId === null ? t('logSaveBtn') : t('saveChangesBtn');
  const tb = document.getElementById('tplSaveBtn');
  if(tb) tb.textContent = editingTemplateId === null ? t('saveTemplateBtn') : t('saveChangesBtn');
}

/* ---------- 5. profiles ---------- */
function openProfiles(){ renderProfileList(); document.getElementById('profileModal').classList.add('show'); }
function closeProfiles(){ document.getElementById('profileModal').classList.remove('show'); }

function profileWorkoutCount(id){
  try {
    const raw = localStorage.getItem('fitpro:p:' + id + ':trainingLog');
    return raw ? (JSON.parse(raw) || []).length : 0;
  } catch(e){ return 0; }
}

function renderProfileList(){
  const c = document.getElementById('profileList');
  if(!c) return;
  c.innerHTML = profiles.map(function(p){
    const initial = esc((p.name || '?').trim().charAt(0).toUpperCase());
    return '<div class="profile-row ' + (p.id === activeProfileId ? 'active' : '') + '">' +
      '<div class="profile-av">' + initial + '</div>' +
      '<div class="profile-nm">' + esc(p.name) +
        '<div class="profile-meta">' + profileWorkoutCount(p.id) + ' ' + esc(t('workoutsCount')) + '</div></div>' +
      (p.id === activeProfileId ? '<span class="badge">✓</span>' :
        '<button class="btn btn-sm" onclick="switchProfile(\'' + esc(p.id) + '\')">' + esc(t('startFromTemplate')) + '</button>') +
      (profiles.length > 1 ? '<button class="icon-action danger" onclick="deleteProfile(\'' + esc(p.id) + '\')" aria-label="' + esc(t('deleteAction')) + '">🗑</button>' : '') +
    '</div>';
  }).join('');
}

function createProfile(){
  const input = document.getElementById('newProfileName');
  const name = input.value.trim();
  if(!name){ flashToast(t('profileNameAlert')); return; }
  const id = 'p' + Date.now();
  profiles.push({ id: id, name: name, createdAt: new Date().toISOString() });
  saveGlobal('profiles', profiles);
  input.value = '';
  switchProfile(id, true);
  flashToast(t('profileCreatedToast'));
}

function switchProfile(id, isNew){
  stopRest();
  clearInterval(workoutTimerHandle);
  activeProfileId = id;
  saveGlobal('activeProfile', id);
  closeProfiles();
  loadProfileData();
  if(!user){
    // brand-new profile has no onboarding data yet
    document.getElementById('mainApp').classList.remove('active');
    document.getElementById('onboardingContainer').classList.remove('hidden');
    document.getElementById('onboardForm').reset();
    calcMacros();
  } else {
    enterApp(true);
    if(!isNew) flashToast(t('profileSwitchedToast'));
  }
}

function deleteProfile(id){
  if(profiles.length <= 1) return;
  if(!confirm(t('profileDeleteConfirm'))) return;
  Object.keys(localStorage).filter(function(k){ return k.indexOf('fitpro:p:' + id + ':') === 0; })
    .forEach(function(k){ localStorage.removeItem(k); });
  profiles = profiles.filter(function(p){ return p.id !== id; });
  saveGlobal('profiles', profiles);
  if(activeProfileId === id) switchProfile(profiles[0].id);
  else renderProfileList();
  flashToast(t('profileDeletedToast'));
}

function loadProfileData(){
  settings     = loadKey('settings', { defaultRestSec: 90, barKg: 20 });
  user         = loadKey('user', null);
  metrics      = loadKey('metrics', null);
  meals        = loadKey('meals', []);
  exercises    = loadKey('exercises', []);
  trainingLog  = loadKey('trainingLog', []);
  templates    = loadKey('templates', []);
  trainingDays = loadKey('trainingDays', [false,false,false,false,false,false,false]);
  migrateDailyLog();
  migrateShapes();
  viewingDate = todayKey();
  restoreSession();
}

/* ---------- 6. macros + onboarding ---------- */
function calculateTDEE(age, gender, weight, height){
  const bmr = gender === 'male'
    ? 88.362 + (13.397*weight) + (4.799*height) - (5.677*age)
    : 447.593 + (9.247*weight) + (3.098*height) - (4.330*age);
  return Math.round(bmr * 1.55);
}
function calculateMacros(tdee, goal, weight){
  let targetCals, pm, fm;
  if(goal === 'weight-loss'){ targetCals = Math.round(tdee - 400); pm = 2.0; fm = 1.0; }
  else if(goal === 'maintenance'){ targetCals = tdee; pm = 1.8; fm = 1.0; }
  else { targetCals = Math.round(tdee + 400); pm = 2.2; fm = 1.1; }
  const protein = Math.round(weight * pm);
  const fats = Math.round(weight * fm);
  const carbs = Math.round((targetCals - protein*4 - fats*9) / 4);
  return { calories: targetCals, protein: protein, carbs: carbs, fats: fats };
}

function calcMacros(){
  const ageEl = document.getElementById('age');
  if(!ageEl) return;
  const age = num(ageEl.value);
  const genderEl = document.querySelector('input[name="gender"]:checked');
  const gender = genderEl ? genderEl.value : null;
  const weight = num(document.getElementById('weight').value);
  const height = num(document.getElementById('height').value);
  const goal = document.getElementById('goal').value;

  if(age > 0 && gender && weight > 0 && height > 0 && goal){
    const m = calculateMacros(calculateTDEE(age, gender, weight, height), goal, weight);
    document.getElementById('cals').textContent = m.calories.toLocaleString();
    document.getElementById('protein').textContent = m.protein;
    document.getElementById('carbs').textContent = m.carbs;
    document.getElementById('fats').textContent = m.fats;
    document.getElementById('goalLabel').textContent = goalLabel(goal);
    document.getElementById('macroDisplay').classList.add('show');
  } else {
    document.getElementById('macroDisplay').classList.remove('show');
  }
}

function setFieldError(id, show){
  const el = document.getElementById(id);
  if(el) el.style.display = show ? 'block' : 'none';
}

function handleSubmit(e){
  e.preventDefault();
  const nameEl = document.getElementById('name');
  const ageEl = document.getElementById('age');
  const weightEl = document.getElementById('weight');
  const heightEl = document.getElementById('height');
  const goalEl = document.getElementById('goal');

  const name = nameEl.value.trim();
  const age = num(ageEl.value);
  const genderEl = document.querySelector('input[name="gender"]:checked');
  const gender = genderEl ? genderEl.value : null;
  const weight = num(weightEl.value);
  const height = num(heightEl.value);
  const goal = goalEl.value;

  const nameValid = !!name;
  const ageValid = ageEl.value !== '' && age >= 13 && age <= 120;
  const weightValid = weightEl.value !== '' && weight >= 20 && weight <= 300;
  const heightValid = heightEl.value !== '' && height >= 100 && height <= 250;
  const goalValid = !!goal;

  setFieldError('nameError', !nameValid);
  setFieldError('ageError', !ageValid);
  setFieldError('weightError', !weightValid);
  setFieldError('heightError', !heightValid);
  setFieldError('goalError', !goalValid);

  if(!nameValid || !ageValid || !weightValid || !heightValid || !goalValid){
    const first = document.getElementById(
      !nameValid ? 'name' : !ageValid ? 'age' : !weightValid ? 'weight' : !heightValid ? 'height' : 'goal');
    first.focus();
    first.scrollIntoView({ behavior:'smooth', block:'center' });
    return;
  }

  if(profiles.length === 0 || !activeProfileId){
    const id = 'p' + Date.now();
    profiles.push({ id: id, name: name, createdAt: new Date().toISOString() });
    activeProfileId = id;
    saveGlobal('profiles', profiles);
    saveGlobal('activeProfile', id);
  } else {
    const p = profiles.find(function(x){ return x.id === activeProfileId; });
    if(p && !p.named){ p.name = name; p.named = true; saveGlobal('profiles', profiles); }
  }

  const tdee = calculateTDEE(age, gender, weight, height);
  user = { name:name, age:age, gender:gender, weight:weight, height:height, goal:goal, createdAt:new Date().toISOString() };
  metrics = { age:age, height:height, weight:weight, tdee:tdee, macroTarget: calculateMacros(tdee, goal, weight) };

  saveKey('user', user);
  saveKey('metrics', metrics);
  saveKey('meals', meals);
  saveKey('exercises', exercises);
  saveKey('trainingLog', trainingLog);
  saveKey('dailyLog', dailyLog);
  saveKey('trainingDays', trainingDays);
  saveKey('templates', templates);
  saveKey('settings', settings);

  // seed today's body weight so the trend chart has a first point
  const dk = todayKey();
  if(!dailyLog[dk]) dailyLog[dk] = { sleep:0, steps:0, bodyKg:0, restHr:0 };
  if(!dailyLog[dk].bodyKg){ dailyLog[dk].bodyKg = weight; saveKey('dailyLog', dailyLog); }

  enterApp();
}

function enterApp(silent){
  document.getElementById('onboardingContainer').classList.add('hidden');
  document.getElementById('mainApp').classList.add('active');
  document.getElementById('greetingText').textContent = translations[currentLang].greeting(user.name);

  renderHero();
  renderDashboardGoal();
  renderMeals();
  renderExercises();
  renderMuscleOptions();
  renderTemplates();
  renderMetricsForm();
  renderTrainingLog();
  renderWeeklyChart();
  renderHistoryStats();
  renderProgress();
  renderDayMetrics();
  renderDayPicker();
  renderSession();
  document.getElementById('liveTimer').textContent = formatTimer(workoutSeconds);
  updateWorkoutButtons();
  updateFormLabels();

  switchScreen('dashboard');
  if(!silent) flashToast(translations[currentLang].welcomeToast(user.name));
}

/* ---------- 7. navigation ---------- */
function openSidebar(){
  document.getElementById('sidebar').classList.add('open');
  document.getElementById('sidebarBackdrop').classList.add('show');
}
function closeSidebar(){
  document.getElementById('sidebar').classList.remove('open');
  document.getElementById('sidebarBackdrop').classList.remove('show');
}
function switchScreen(name, btn){
  closeSidebar();
  document.querySelectorAll('.screen').forEach(function(s){ s.classList.remove('active'); });
  const target = document.getElementById(name);
  if(target) target.classList.add('active');
  document.querySelectorAll('.nav-btn').forEach(function(b){ b.classList.remove('active'); });
  if(btn) btn.classList.add('active');
  else {
    const m = document.querySelector('.nav-btn[data-screen="' + name + '"]');
    if(m) m.classList.add('active');
  }
  if(name === 'history') renderHistoryStats();
  if(name === 'progress') renderProgress();
}

function showNotificationsToast(){ flashToast(t('notificationsToast')); }
function showSearchToast(){ flashToast(t('searchComingSoon')); }
function showInfoToast(){ flashToast(t('liveInfoToast')); }
function showProfileToast(){ openProfiles(); }

/* ---------- 8. dashboard ---------- */
function renderDashboardGoal(){
  if(!metrics) return;
  const g = metrics.macroTarget;
  document.getElementById('dashGoalLabel').textContent = goalLabel(user.goal);
  document.getElementById('dashCalGoal').textContent = g.calories.toLocaleString() + ' ' + t('calUnitShort');
  document.getElementById('dashProtGoal').textContent = g.protein + t('gramUnit');
  document.getElementById('dashCarbGoal').textContent = g.carbs + t('gramUnit');
  document.getElementById('dashFatGoal').textContent = g.fats + t('gramUnit');
  const eaten = meals.reduce(function(s,m){ return s + num(m.cal); }, 0);
  document.getElementById('dashCalBar').style.width = Math.min(100, (eaten/g.calories)*100) + '%';
}

function renderHero(){
  const badgeEl = document.getElementById('heroBadge');
  if(!badgeEl) return;
  const today = new Date();
  document.getElementById('heroDay').textContent = String(today.getDate()).padStart(2,'0');
  document.getElementById('heroMonth').textContent = t('monthNames')[today.getMonth()];
  badgeEl.textContent = trainingDays[today.getDay()] ? t('heroTrainingDay') : t('heroRestDay');

  const todayLogs = trainingLog.filter(function(e){
    return new Date(e.dateISO).toDateString() === today.toDateString();
  });
  const minutes = todayLogs.reduce(function(s,e){ return s + num(e.durationMin); }, 0);
  const calories = todayLogs.reduce(function(s,e){ return s + num(e.calories); }, 0);

  document.getElementById('heroExCount').textContent = exercises.length;
  document.getElementById('heroMinutes').textContent = minutes;
  document.getElementById('heroCalories').textContent = calories.toLocaleString();

  if(exercises.length === 0){
    document.getElementById('heroTitle').textContent = t('heroNoProgram');
    document.getElementById('heroMeta').textContent = t('heroMetaNoProgram');
  } else {
    document.getElementById('heroTitle').textContent = t('heroProgramReady');
    document.getElementById('heroMeta').textContent =
      exercises.length + ' ' + t('heroExercisesLabel') + ' · ' + todayLogs.length + ' ' + t('heroTodayLogged');
  }
}

function renderWeeklyChart(){
  const track = document.getElementById('weeklyChartTrack');
  if(!track) return;
  const today = new Date();
  const days = [];
  for(let i = 6; i >= 0; i--){ const d = new Date(today); d.setDate(d.getDate()-i); days.push(d); }
  const totals = days.map(function(d){
    return trainingLog.filter(function(e){ return new Date(e.dateISO).toDateString() === d.toDateString(); })
                      .reduce(function(s,e){ return s + num(e.durationMin); }, 0);
  });
  const max = Math.max.apply(null, totals.concat([30]));
  const names = t('dayNamesShort');
  track.innerHTML = totals.map(function(min, i){
    const h = Math.max(4, (min/max)*100);
    return '<div style="flex:1; display:flex; flex-direction:column; align-items:center; gap:4px; height:100%; justify-content:flex-end;">' +
      '<div style="width:100%; height:' + h + '%; background:' + (min>0 ? '#d7ff2b' : '#2a2a2a') + '; border-radius:4px 4px 0 0;" title="' + min + '"></div>' +
      '<div style="font-size:9px; color:#6f6f6f;">' + esc(names[days[i].getDay()]) + '</div>' +
    '</div>';
  }).join('');
}

/* ---------- 9. daily metrics with real per-date history ---------- */
const SLEEP_GOAL_HOURS = 8;
const STEPS_GOAL = 10000;

function dayEntry(key){
  if(!dailyLog[key]) dailyLog[key] = { sleep:0, steps:0, bodyKg:0, restHr:0 };
  return dailyLog[key];
}

function shiftViewingDate(delta){
  const d = new Date(viewingDate + 'T12:00:00');
  d.setDate(d.getDate() + delta);
  const k = dayKey(d);
  if(k > todayKey()) return;            // no logging into the future
  viewingDate = k;
  renderDayMetrics();
}

function dayLabel(key){
  if(key === todayKey()) return t('todayLabel');
  const y = new Date(); y.setDate(y.getDate()-1);
  if(key === dayKey(y)) return t('yesterdayLabel');
  const d = new Date(key + 'T12:00:00');
  return d.toLocaleDateString(currentLang === 'he' ? 'he-IL' : 'en-US',
    { weekday:'short', day:'2-digit', month:'short' });
}

function renderDayMetrics(){
  const lbl = document.getElementById('dateNavLabel');
  if(!lbl) return;
  if(!viewingDate) viewingDate = todayKey();
  const e = dayEntry(viewingDate);
  lbl.textContent = dayLabel(viewingDate);
  document.getElementById('dateNextBtn').disabled = viewingDate >= todayKey();

  document.getElementById('sleepInput').value = e.sleep || '';
  document.getElementById('stepsInput').value = e.steps || '';
  document.getElementById('bodyKgInput').value = e.bodyKg || '';
  document.getElementById('restHrInput').value = e.restHr || '';
  document.getElementById('sleepBar').style.width = Math.min(100, (e.sleep/SLEEP_GOAL_HOURS)*100) + '%';
  document.getElementById('stepsBar').style.width = Math.min(100, (e.steps/STEPS_GOAL)*100) + '%';
}

function saveDayMetric(field){
  const e = dayEntry(viewingDate);
  const map = { sleep:'sleepInput', steps:'stepsInput', bodyKg:'bodyKgInput', restHr:'restHrInput' };
  e[field] = Math.max(0, num(document.getElementById(map[field]).value));
  saveKey('dailyLog', dailyLog);

  // body weight is a real input to TDEE — keep goals honest when it changes
  if(field === 'bodyKg' && e.bodyKg > 0 && metrics && user){
    metrics.weight = e.bodyKg;
    user.weight = e.bodyKg;
    metrics.tdee = calculateTDEE(metrics.age, user.gender, e.bodyKg, metrics.height);
    metrics.macroTarget = calculateMacros(metrics.tdee, user.goal, e.bodyKg);
    saveKey('metrics', metrics);
    saveKey('user', user);
    renderDashboardGoal();
    renderNutritionSummary();
    renderMetricsForm();
    flashToast(t('bodyWeightSyncedToast'));
  } else {
    flashToast(t('metricsSavedToast'));
  }
  renderDayMetrics();
  renderProgress();
}

/* ---------- 10. program: exercises, templates, day picker ---------- */
function renderMuscleOptions(){
  const sel = document.getElementById('exMuscle');
  if(!sel) return;
  const cur = sel.value;
  sel.innerHTML = MUSCLES.map(function(m){
    return '<option value="' + m + '">' + esc(muscleLabel(m)) + '</option>';
  }).join('');
  if(cur) sel.value = cur;
}

function renderDayPicker(){
  const c = document.getElementById('dayPicker');
  if(!c) return;
  const today = new Date().getDay();
  c.innerHTML = t('dayNamesShort').map(function(n, i){
    return '<button class="day-btn ' + (trainingDays[i] ? 'selected' : '') + ' ' + (i === today ? 'today' : '') +
      '" onclick="toggleTrainingDay(' + i + ')">' + esc(n) + '</button>';
  }).join('');
}
function toggleTrainingDay(i){
  trainingDays[i] = !trainingDays[i];
  saveKey('trainingDays', trainingDays);
  renderDayPicker();
  renderHero();
}

function toggleExerciseForm(show){
  document.getElementById('exerciseForm').classList.toggle('show', show);
  if(!show){
    editingExerciseIndex = null;
    ['exName','exTag','exSets','exReps','exKg','exRest'].forEach(function(id){
      const el = document.getElementById(id); if(el) el.value = '';
    });
  }
  updateFormLabels();
}

function saveExercise(){
  const name = document.getElementById('exName').value.trim();
  if(!name){ flashToast(t('exerciseNameAlert')); return; }
  /* sets/reps used to be stored as the raw input string, so "-5" went straight
     into the record. Everything numeric here is clamped to a sane floor: a
     negative set count, rep count, load or rest interval is never meaningful. */
  const payload = {
    name: name,
    tag: document.getElementById('exTag').value.trim() || t('generalTag'),
    muscle: document.getElementById('exMuscle').value || 'other',
    sets: String(posInt(document.getElementById('exSets').value, 3)),
    reps: String(posInt(document.getElementById('exReps').value, 10)),
    targetKg: Math.max(0, num(document.getElementById('exKg').value)),
    restSec: posInt(document.getElementById('exRest').value, settings.defaultRestSec)
  };
  const isEdit = editingExerciseIndex !== null;
  if(isEdit){
    payload.id = exercises[editingExerciseIndex].id;
    exercises[editingExerciseIndex] = payload;
  } else {
    payload.id = 'e' + Date.now().toString(36) + Math.random().toString(36).slice(2,5);
    exercises.push(payload);
  }
  saveKey('exercises', exercises);
  editingExerciseIndex = null;
  renderExercises();
  renderHero();
  renderTemplateExPicker();
  toggleExerciseForm(false);
  flashToast(isEdit ? t('exerciseUpdatedToast') : t('exerciseSavedToast'));
}

function editExercise(i){
  const ex = exercises[i];
  if(!ex) return;
  editingExerciseIndex = i;
  document.getElementById('exName').value = ex.name || '';
  document.getElementById('exTag').value = ex.tag || '';
  document.getElementById('exMuscle').value = ex.muscle || 'other';
  document.getElementById('exSets').value = ex.sets || '';
  document.getElementById('exReps').value = ex.reps || '';
  document.getElementById('exKg').value = ex.targetKg || '';
  document.getElementById('exRest').value = ex.restSec || '';
  const f = document.getElementById('exerciseForm');
  f.classList.add('show');
  updateFormLabels();
  f.scrollIntoView({ behavior:'smooth', block:'center' });
}

function deleteExercise(i){
  if(!exercises[i]) return;
  exercises.splice(i, 1);
  saveKey('exercises', exercises);
  if(editingExerciseIndex !== null) toggleExerciseForm(false);
  renderExercises();
  renderHero();
  renderTemplateExPicker();
  flashToast(t('exerciseDeletedToast'));
}

function renderExercises(){
  const c = document.getElementById('exercisesGrid');
  if(!c) return;
  if(exercises.length === 0){
    c.innerHTML = '<div class="log-empty" style="grid-column:1/-1;">' + esc(t('exercisesEmptyState')) + '</div>';
    return;
  }
  c.innerHTML = exercises.map(function(ex, i){
    const best = bestE1RM(ex.name);
    return '<div class="ex-card">' +
      '<div class="ex-thumb">🏋️</div>' +
      '<div class="ex-body">' +
        '<div class="ex-name">' + esc(displayExerciseName(ex)) + '</div>' +
        '<div class="ex-meta">' + esc(ex.sets) + ' ' + esc(t('setsUnit')) + ' × ' + esc(ex.reps) +
          (num(ex.targetKg) > 0 ? ' · ' + num(ex.targetKg) + ' ' + esc(t('kgUnit')) : '') + '</div>' +
        (best > 0 ? '<div class="ex-meta">' + esc(t('e1rmLabel')) + ': ' + best.toFixed(1) + ' ' + esc(t('kgUnit')) + '</div>' : '') +
        '<div class="ex-tags"><span class="tag muscle">' + esc(muscleLabel(ex.muscle)) + '</span></div>' +
        '<div class="card-actions" style="margin-top:6px;">' +
          '<button class="icon-action" onclick="editExercise(' + i + ')" aria-label="' + esc(t('editAction')) + '">✎</button>' +
          '<button class="icon-action danger" onclick="deleteExercise(' + i + ')" aria-label="' + esc(t('deleteAction')) + '">🗑</button>' +
        '</div>' +
      '</div>' +
    '</div>';
  }).join('');
}

function renderMetricsForm(){
  if(!metrics) return;
  const a = document.getElementById('metricAge');
  if(!a) return;
  a.value = metrics.age;
  document.getElementById('metricHeight').value = metrics.height;
  document.getElementById('metricWeight').value = metrics.weight;
}

function updateMetrics(){
  const age = num(document.getElementById('metricAge').value) || metrics.age;
  const height = num(document.getElementById('metricHeight').value) || metrics.height;
  const weight = num(document.getElementById('metricWeight').value) || metrics.weight;
  const tdee = calculateTDEE(age, user.gender, weight, height);
  metrics = { age:age, height:height, weight:weight, tdee:tdee, macroTarget: calculateMacros(tdee, user.goal, weight) };
  user.age = age; user.height = height; user.weight = weight;
  saveKey('metrics', metrics);
  saveKey('user', user);
  renderDashboardGoal();
  renderNutritionSummary();
  flashToast(t('metricsUpdatedToast'));
}

/* templates */
function toggleTemplateForm(show){
  document.getElementById('templateForm').classList.toggle('show', show);
  if(show) renderTemplateExPicker();
  else { editingTemplateId = null; document.getElementById('tplName').value = ''; }
  updateFormLabels();
}

function renderTemplateExPicker(preIds){
  const c = document.getElementById('tplExPicker');
  if(!c) return;
  const pre = preIds || [];
  if(exercises.length === 0){
    c.innerHTML = '<div class="exercise-check-empty">' + esc(t('noExercisesYet')) + '</div>';
    return;
  }
  c.innerHTML = exercises.map(function(ex){
    return '<label><input type="checkbox" class="tpl-ex-check" value="' + esc(ex.id) + '"' +
      (pre.indexOf(ex.id) !== -1 ? ' checked' : '') + '> ' + esc(displayExerciseName(ex)) + '</label>';
  }).join('');
}

function saveTemplate(){
  const name = document.getElementById('tplName').value.trim();
  if(!name){ flashToast(t('templateNameAlert')); return; }
  const ids = Array.from(document.querySelectorAll('.tpl-ex-check:checked')).map(function(cb){ return cb.value; });
  if(ids.length === 0){ flashToast(t('templateExAlert')); return; }
  if(editingTemplateId){
    const tpl = templates.find(function(x){ return x.id === editingTemplateId; });
    if(tpl){ tpl.name = name; tpl.exerciseIds = ids; }
  } else {
    templates.push({ id:'t' + Date.now(), name:name, exerciseIds:ids });
  }
  saveKey('templates', templates);
  editingTemplateId = null;
  renderTemplates();
  toggleTemplateForm(false);
  flashToast(t('templateSavedToast'));
}

function editTemplate(id){
  const tpl = templates.find(function(x){ return x.id === id; });
  if(!tpl) return;
  editingTemplateId = id;
  document.getElementById('tplName').value = tpl.name;
  document.getElementById('templateForm').classList.add('show');
  renderTemplateExPicker(tpl.exerciseIds);
  updateFormLabels();
}

function deleteTemplate(id){
  templates = templates.filter(function(x){ return x.id !== id; });
  saveKey('templates', templates);
  renderTemplates();
  flashToast(t('templateDeletedToast'));
}

function renderTemplates(){
  const c = document.getElementById('templatesList');
  if(!c) return;
  if(templates.length === 0){
    c.innerHTML = '<div class="log-empty">' + esc(t('templatesEmpty')) + '</div>';
    return;
  }
  c.innerHTML = templates.map(function(tpl){
    const names = tpl.exerciseIds.map(function(id){
      const ex = exercises.find(function(e){ return e.id === id; });
      return ex ? displayExerciseName(ex) : null;
    }).filter(Boolean);
    return '<div class="log-entry">' +
      '<div class="log-entry-info">' +
        '<div class="log-entry-name">' + esc(tpl.name) + '</div>' +
        '<div class="log-entry-chips">' + names.map(function(n){ return '<span class="tag">' + esc(n) + '</span>'; }).join('') + '</div>' +
      '</div>' +
      '<div class="card-actions">' +
        '<button class="btn btn-sm btn-accent" onclick="startFromTemplate(\'' + esc(tpl.id) + '\')">' + esc(t('startFromTemplate')) + '</button>' +
        '<button class="icon-action" onclick="editTemplate(\'' + esc(tpl.id) + '\')" aria-label="' + esc(t('editAction')) + '">✎</button>' +
        '<button class="icon-action danger" onclick="deleteTemplate(\'' + esc(tpl.id) + '\')" aria-label="' + esc(t('deleteAction')) + '">🗑</button>' +
      '</div>' +
    '</div>';
  }).join('');
}

/* ---------- 11. live workout ---------- */
let workoutState = 'idle';    // idle | running | paused
let workoutSeconds = 0;
let workoutTimerHandle = null;
let session = { name:'', entries: [] };   // entries: {exId,name,muscle,restSec,sets:[{kg,reps,done}]}

function formatTimer(sec){
  const h = String(Math.floor(sec/3600)).padStart(2,'0');
  const m = String(Math.floor((sec%3600)/60)).padStart(2,'0');
  const s = String(sec%60).padStart(2,'0');
  return h + ':' + m + ':' + s;
}

function persistWorkout(){
  saveKey('workout', { state: workoutState, seconds: workoutSeconds, session: session });
}
function restoreSession(){
  const w = loadKey('workout', null);
  workoutSeconds = 0; workoutState = 'idle'; session = { name:'', entries: [] };
  if(w && (num(w.seconds) > 0 || (w.session && w.session.entries && w.session.entries.length))){
    workoutSeconds = num(w.seconds);
    workoutState = 'paused';           // never resume counting time the user wasn't training
    if(w.session) session = w.session;
    return true;
  }
  return false;
}

function tickWorkout(){
  workoutSeconds++;
  const el = document.getElementById('liveTimer');
  if(el) el.textContent = formatTimer(workoutSeconds);
  // Persist every tick: throttling this to every 5s meant a reload in the gap
  // silently threw away the elapsed time. The record is small; the write is cheap.
  persistWorkout();
}

function startWorkout(){
  workoutState = 'running';
  clearInterval(workoutTimerHandle);
  workoutTimerHandle = setInterval(tickWorkout, 1000);
  if(session.entries.length === 0) seedSessionFromProgram();
  persistWorkout();
  updateWorkoutButtons();
  renderSession();
}
function pauseWorkout(){
  workoutState = 'paused';
  clearInterval(workoutTimerHandle);
  persistWorkout();
  updateWorkoutButtons();
}

/* An empty session is useless, so open with whatever the program already has. */
function seedSessionFromProgram(){
  session.entries = exercises.map(function(ex){
    return { exId: ex.id, name: ex.name, muscle: ex.muscle || 'other',
             restSec: num(ex.restSec) || settings.defaultRestSec,
             sets: [ { kg: num(ex.targetKg), reps: num(ex.reps) || 0, done: false } ] };
  });
}

function startFromTemplate(id){
  const tpl = templates.find(function(x){ return x.id === id; });
  if(!tpl) return;
  session.name = tpl.name;
  session.entries = tpl.exerciseIds.map(function(exId){
    const ex = exercises.find(function(e){ return e.id === exId; });
    if(!ex) return null;
    return { exId: ex.id, name: ex.name, muscle: ex.muscle || 'other',
             restSec: num(ex.restSec) || settings.defaultRestSec,
             sets: [ { kg: num(ex.targetKg), reps: num(ex.reps) || 0, done: false } ] };
  }).filter(Boolean);
  workoutState = 'running';
  workoutSeconds = 0;
  clearInterval(workoutTimerHandle);
  workoutTimerHandle = setInterval(tickWorkout, 1000);
  persistWorkout();
  updateWorkoutButtons();
  renderSession();
  switchScreen('live');
  flashToast(t('templateStartedToast'));
}

function updateWorkoutButtons(){
  const startBtn = document.getElementById('startWorkoutBtn');
  if(!startBtn) return;
  const pauseBtn = document.getElementById('pauseWorkoutBtn');
  const finishBtn = document.getElementById('finishWorkoutBtn');
  const statusEl = document.getElementById('liveWorkoutStatus');
  if(workoutState === 'idle'){
    startBtn.style.display = ''; startBtn.textContent = t('startWorkoutCta');
    pauseBtn.style.display = 'none'; finishBtn.style.display = 'none';
    statusEl.textContent = t('notStartedLabel');
  } else if(workoutState === 'running'){
    startBtn.style.display = 'none';
    pauseBtn.style.display = ''; pauseBtn.textContent = t('pauseBtn');
    finishBtn.style.display = ''; finishBtn.textContent = t('finishWorkoutBtn');
    statusEl.textContent = t('inProgressLabel');
  } else {
    startBtn.style.display = ''; startBtn.textContent = t('resumeBtn');
    pauseBtn.style.display = 'none';
    finishBtn.style.display = ''; finishBtn.textContent = t('finishWorkoutBtn');
    statusEl.textContent = t('pausedLabel');
  }
}

/* Epley estimate — the standard way to compare sets at different rep ranges. */
function e1rm(kg, reps){
  if(kg <= 0 || reps <= 0) return 0;
  return kg * (1 + reps/30);
}
function bestE1RM(exName, beforeISO){
  let best = 0;
  trainingLog.forEach(function(en){
    if(beforeISO && en.dateISO >= beforeISO) return;
    (en.entries || []).forEach(function(it){
      if(it.name !== exName) return;
      (it.sets || []).forEach(function(s){
        const v = e1rm(num(s.kg), num(s.reps));
        if(v > best) best = v;
      });
    });
  });
  return best;
}

/* The single most useful number while training: what you did last time. */
function lastPerformance(exName){
  for(let i = 0; i < trainingLog.length; i++){
    const en = trainingLog[i];
    const it = (en.entries || []).find(function(x){
      return x.name === exName && (x.sets || []).some(function(s){ return num(s.kg) > 0 || num(s.reps) > 0; });
    });
    if(it) return { dateISO: en.dateISO, sets: it.sets };
  }
  return null;
}

function renderSession(){
  const c = document.getElementById('sessionExercises');
  if(!c) return;
  const wrap = document.getElementById('sessionCard');
  if(wrap) wrap.style.display = workoutState === 'idle' ? 'none' : '';
  if(workoutState === 'idle'){ c.innerHTML = ''; return; }

  if(session.entries.length === 0){
    c.innerHTML = '<div class="log-empty">' + esc(t('sessionEmpty')) + '</div>';
    return;
  }

  c.innerHTML = session.entries.map(function(it, ei){
    const last = lastPerformance(it.name);
    let lastHtml;
    if(last){
      const when = new Date(last.dateISO).toLocaleDateString(currentLang === 'he' ? 'he-IL' : 'en-US', { day:'2-digit', month:'short' });
      lastHtml = esc(t('lastTimeLabel')) + ' <b>' +
        last.sets.filter(function(s){ return num(s.kg) > 0 || num(s.reps) > 0; })
          .map(function(s){ return num(s.kg) + '×' + num(s.reps); }).join(', ') +
        '</b> · ' + esc(when);
    } else {
      lastHtml = esc(t('noLastTime'));
    }
    const allDone = it.sets.length > 0 && it.sets.every(function(s){ return s.done; });
    const prev = bestE1RM(it.name);

    const rows = it.sets.map(function(s, si){
      const isPR = prev > 0 && e1rm(num(s.kg), num(s.reps)) > prev;
      return '<div class="set-row">' +
        '<div class="set-num">' + (si+1) + '</div>' +
        '<input class="set-input' + (isPR ? ' pr' : '') + '" type="number" inputmode="decimal" step="0.5" min="0" value="' + (s.kg || '') + '" ' +
          'onchange="updateSet(' + ei + ',' + si + ',\'kg\',this.value)" aria-label="' + esc(t('setColKg')) + '">' +
        '<input class="set-input" type="number" inputmode="numeric" min="0" value="' + (s.reps || '') + '" ' +
          'onchange="updateSet(' + ei + ',' + si + ',\'reps\',this.value)" aria-label="' + esc(t('setColReps')) + '">' +
        '<button class="set-done-btn' + (s.done ? ' on' : '') + '" onclick="toggleSetDone(' + ei + ',' + si + ')" aria-label="' + esc(t('setColDone')) + '">✓</button>' +
        '<button class="set-del-btn" onclick="removeSet(' + ei + ',' + si + ')" aria-label="' + esc(t('deleteAction')) + '">✕</button>' +
      '</div>';
    }).join('');

    return '<div class="session-ex' + (allDone ? ' done' : '') + '">' +
      '<div class="session-ex-head">' +
        '<div style="min-width:0;">' +
          '<div class="session-ex-name">' + esc(it.name) + '</div>' +
          '<div class="session-ex-last">' + lastHtml + '</div>' +
        '</div>' +
        '<div class="card-actions">' +
          '<span class="tag muscle">' + esc(muscleLabel(it.muscle)) + '</span>' +
          '<button class="icon-action danger" onclick="removeSessionExercise(' + ei + ')" aria-label="' + esc(t('deleteAction')) + '">🗑</button>' +
        '</div>' +
      '</div>' +
      '<div class="set-head"><div>' + esc(t('setColSet')) + '</div><div>' + esc(t('setColKg')) + '</div>' +
        '<div>' + esc(t('setColReps')) + '</div><div>' + esc(t('setColDone')) + '</div><div></div></div>' +
      rows +
      '<button class="add-set-btn" onclick="addSet(' + ei + ')">' + esc(t('addSetBtn')) + '</button>' +
    '</div>';
  }).join('');
}

function updateSet(ei, si, field, value){
  const it = session.entries[ei];
  if(!it || !it.sets[si]) return;
  it.sets[si][field] = Math.max(0, num(value));
  persistWorkout();
  markPR(ei, si);
}

/* Refresh one row's PR highlight in place. A full renderSession() here would
   steal focus from the input the user is still typing in. */
function markPR(ei, si){
  const it = session.entries[ei];
  if(!it || !it.sets[si]) return;
  const card = document.querySelectorAll('#sessionExercises .session-ex')[ei];
  if(!card) return;
  const row = card.querySelectorAll('.set-row')[si];
  if(!row) return;
  const kgInput = row.querySelector('.set-input');
  if(!kgInput) return;
  const prev = bestE1RM(it.name);
  const s = it.sets[si];
  kgInput.classList.toggle('pr', prev > 0 && e1rm(num(s.kg), num(s.reps)) > prev);
}

function toggleSetDone(ei, si){
  const it = session.entries[ei];
  if(!it || !it.sets[si]) return;
  const s = it.sets[si];
  s.done = !s.done;
  persistWorkout();
  renderSession();
  // finishing a set is exactly when the rest clock should start
  if(s.done) startRest(num(it.restSec) || settings.defaultRestSec);
}

function addSet(ei){
  const it = session.entries[ei];
  if(!it) return;
  const lastSet = it.sets[it.sets.length-1];
  it.sets.push({ kg: lastSet ? lastSet.kg : 0, reps: lastSet ? lastSet.reps : 0, done: false });
  persistWorkout();
  renderSession();
}
function removeSet(ei, si){
  const it = session.entries[ei];
  if(!it) return;
  it.sets.splice(si, 1);
  persistWorkout();
  renderSession();
}
function removeSessionExercise(ei){
  session.entries.splice(ei, 1);
  persistWorkout();
  renderSession();
}

function openAddToSession(){
  const c = document.getElementById('sessionExPicker');
  if(!c) return;
  const modal = document.getElementById('sessionExModal');
  if(exercises.length === 0){
    c.innerHTML = '<div class="exercise-check-empty">' + esc(t('noExercisesYet')) + '</div>';
  } else {
    c.innerHTML = exercises.map(function(ex){
      return '<div class="profile-row" onclick="addExerciseToSession(\'' + esc(ex.id) + '\')">' +
        '<div class="profile-av">🏋️</div>' +
        '<div class="profile-nm">' + esc(displayExerciseName(ex)) +
        '<div class="profile-meta">' + esc(muscleLabel(ex.muscle)) + '</div></div></div>';
    }).join('');
  }
  modal.classList.add('show');
}
function closeAddToSession(){ document.getElementById('sessionExModal').classList.remove('show'); }

function addExerciseToSession(exId){
  const ex = exercises.find(function(e){ return e.id === exId; });
  if(!ex) return;
  session.entries.push({ exId: ex.id, name: ex.name, muscle: ex.muscle || 'other',
    restSec: num(ex.restSec) || settings.defaultRestSec,
    sets: [ { kg: num(ex.targetKg), reps: num(ex.reps) || 0, done: false } ] });
  persistWorkout();
  renderSession();
  closeAddToSession();
}

/* rest timer */
let restRemaining = 0;
let restHandle = null;

function startRest(sec){
  if(!sec || sec <= 0) return;
  restRemaining = sec;
  clearInterval(restHandle);
  restHandle = setInterval(tickRest, 1000);
  updateRestUI();
}
function tickRest(){
  restRemaining--;
  if(restRemaining <= 0){
    stopRest();
    beep();
    flashToast(t('restDoneToast'));
    return;
  }
  updateRestUI();
}
function stopRest(){
  clearInterval(restHandle);
  restHandle = null;
  restRemaining = 0;
  updateRestUI();
}
function addRest(sec){
  if(restRemaining > 0){ restRemaining += sec; updateRestUI(); }
}
function updateRestUI(){
  const bar = document.getElementById('restBar');
  if(!bar) return;
  bar.classList.toggle('show', restRemaining > 0);
  const timeEl = document.getElementById('restTime');
  if(timeEl){
    const m = String(Math.floor(restRemaining/60)).padStart(2,'0');
    const s = String(restRemaining%60).padStart(2,'0');
    timeEl.textContent = m + ':' + s;
  }
  const lbl = document.getElementById('restLabelEl');
  if(lbl) lbl.textContent = t('restLabel');
  const skip = document.getElementById('restSkipBtn');
  if(skip) skip.textContent = t('restSkip');
  const plus = document.getElementById('restPlusBtn');
  if(plus) plus.textContent = t('restPlus');
}

/* Short tone via WebAudio — no asset to load, works offline. */
function beep(){
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if(!Ctx) return;
    const ctx = new Ctx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain); gain.connect(ctx.destination);
    osc.frequency.value = 880;
    gain.gain.setValueAtTime(0.25, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
    osc.start(); osc.stop(ctx.currentTime + 0.4);
    setTimeout(function(){ ctx.close(); }, 700);
  } catch(e){ /* audio blocked until user gesture — not fatal */ }
}

function finishWorkout(){
  clearInterval(workoutTimerHandle);
  workoutState = 'paused';
  stopRest();
  persistWorkout();
  updateWorkoutButtons();

  editingLogId = null;
  document.getElementById('logName').value = session.name || '';
  document.getElementById('logDuration').value = Math.max(1, Math.round(workoutSeconds/60));
  document.getElementById('logCalories').value = '';
  document.getElementById('logNotes').value = '';
  updateFormLabels();
  const form = document.getElementById('workoutLogForm');
  form.classList.add('show');
  form.scrollIntoView({ behavior:'smooth', block:'center' });
}

function cancelWorkoutLog(){
  editingLogId = null;
  updateFormLabels();
  document.getElementById('workoutLogForm').classList.remove('show');
}

function saveTrainingLog(){
  const name = document.getElementById('logName').value.trim() || t('logNameDefault');
  const duration = num(document.getElementById('logDuration').value) || Math.max(1, Math.round(workoutSeconds/60));
  const calories = num(document.getElementById('logCalories').value);
  const notes = document.getElementById('logNotes').value.trim();
  const isEdit = editingLogId !== null;

  if(isEdit){
    const idx = trainingLog.findIndex(function(e){ return e.id === editingLogId; });
    if(idx !== -1){
      trainingLog[idx] = Object.assign({}, trainingLog[idx],
        { name:name, durationMin:duration, calories:calories, notes:notes });
    }
    editingLogId = null;
    saveKey('trainingLog', trainingLog);
  } else {
    // keep only sets that actually carry data
    const entries = session.entries.map(function(it){
      return { exId: it.exId, name: it.name, muscle: it.muscle,
        sets: (it.sets || []).filter(function(s){ return num(s.kg) > 0 || num(s.reps) > 0; })
                             .map(function(s){ return { kg:num(s.kg), reps:num(s.reps) }; }) };
    }).filter(function(it){ return it.sets.length > 0; });

    // PRs must be measured against history *before* this entry is inserted
    const prs = [];
    entries.forEach(function(it){
      const prev = bestE1RM(it.name);
      let bestNow = 0;
      it.sets.forEach(function(s){ const v = e1rm(s.kg, s.reps); if(v > bestNow) bestNow = v; });
      if(bestNow > prev && prev > 0) prs.push(it.name);
    });

    trainingLog.unshift({
      id: Date.now(),
      dateISO: new Date().toISOString(),
      name:name, durationMin:duration, calories:calories, notes:notes,
      entries: entries,
      exerciseNames: entries.map(function(it){ return it.name; })
    });
    saveKey('trainingLog', trainingLog);

    clearInterval(workoutTimerHandle);
    workoutState = 'idle';
    workoutSeconds = 0;
    session = { name:'', entries: [] };
    document.getElementById('liveTimer').textContent = formatTimer(0);
    persistWorkout();
    updateWorkoutButtons();
    renderSession();

    if(prs.length) setTimeout(function(){ flashToast(t('prToast') + ' ' + prs.join(', ')); }, 1200);
  }

  document.getElementById('workoutLogForm').classList.remove('show');
  updateFormLabels();
  renderTrainingLog();
  renderWeeklyChart();
  renderHero();
  renderHistoryStats();
  renderProgress();
  renderExercises();
  flashToast(isEdit ? t('logUpdatedToast') : t('logSavedToast'));
}

/* ---------- 12. training log ---------- */
function editTrainingLog(id){
  const entry = trainingLog.find(function(e){ return e.id === id; });
  if(!entry) return;
  editingLogId = id;
  document.getElementById('logName').value = entry.name || '';
  document.getElementById('logDuration').value = entry.durationMin || '';
  document.getElementById('logCalories').value = entry.calories || '';
  document.getElementById('logNotes').value = entry.notes || '';
  updateFormLabels();
  const form = document.getElementById('workoutLogForm');
  form.classList.add('show');
  form.scrollIntoView({ behavior:'smooth', block:'center' });
}

function deleteTrainingLog(id){
  trainingLog = trainingLog.filter(function(e){ return e.id !== id; });
  saveKey('trainingLog', trainingLog);
  if(editingLogId === id){
    editingLogId = null;
    document.getElementById('workoutLogForm').classList.remove('show');
    updateFormLabels();
  }
  renderTrainingLog();
  renderWeeklyChart();
  renderHero();
  renderHistoryStats();
  renderProgress();
  renderExercises();
  flashToast(t('logDeletedToast'));
}

function formatLogDate(iso){
  return new Date(iso).toLocaleDateString(currentLang === 'he' ? 'he-IL' : 'en-US', { day:'2-digit', month:'short' });
}

function entryVolume(en){
  let v = 0;
  (en.entries || []).forEach(function(it){
    (it.sets || []).forEach(function(s){ v += num(s.kg) * num(s.reps); });
  });
  return v;
}

function renderTrainingLog(){
  const list = document.getElementById('trainingLogList');
  if(!list) return;
  document.getElementById('logCount').textContent = trainingLog.length;
  if(trainingLog.length === 0){
    list.innerHTML = '<div class="log-empty">' + esc(t('logEmptyState')) + '</div>';
    return;
  }
  list.innerHTML = trainingLog.map(function(en){
    const vol = entryVolume(en);
    const chips = (en.entries || []).map(function(it){
      const setTxt = (it.sets || []).length
        ? ' ' + it.sets.map(function(s){ return num(s.kg) + '×' + num(s.reps); }).join('/')
        : '';
      return '<span class="tag">' + esc(it.name) + esc(setTxt) + '</span>';
    }).join('');
    return '<div class="log-entry">' +
      '<div class="log-entry-info">' +
        '<div class="log-entry-date">' + esc(formatLogDate(en.dateISO)) + '</div>' +
        '<div class="log-entry-name">' + esc(en.name) + '</div>' +
        '<div class="log-entry-meta">⏱ ' + num(en.durationMin) + ' ' + esc(t('minUnit')) +
          (en.calories ? ' · 🔥 ' + num(en.calories) + ' ' + esc(t('calUnitShort')) : '') +
          (vol > 0 ? ' · 🏋 ' + vol.toLocaleString() + ' ' + esc(t('kgUnit')) : '') + '</div>' +
        (chips ? '<div class="log-entry-chips">' + chips + '</div>' : '') +
        (en.notes ? '<div class="log-entry-meta" style="margin-top:4px;">' + esc(en.notes) + '</div>' : '') +
      '</div>' +
      '<div class="card-actions">' +
        '<button class="icon-action" onclick="editTrainingLog(' + en.id + ')" aria-label="' + esc(t('editAction')) + '">✎</button>' +
        '<button class="icon-action danger" onclick="deleteTrainingLog(' + en.id + ')" aria-label="' + esc(t('deleteAction')) + '">🗑</button>' +
      '</div>' +
    '</div>';
  }).join('');
}

/* ---------- 13. history + charts + volume ---------- */
function statLine(count, mins, cals, vol){
  const parts = [ count + ' ' + t('workoutsUnit'), mins + ' ' + t('heroMinutesLabel') ];
  if(cals > 0) parts.push(cals.toLocaleString() + ' ' + t('calUnitShort'));
  if(vol > 0) parts.push(vol.toLocaleString() + ' ' + t('kgUnit'));
  return parts.join(' · ');
}

function renderHistoryStats(){
  const weeklyC = document.getElementById('weeklyStatsContainer');
  const monthlyC = document.getElementById('monthlyTrendsContainer');
  const totalC = document.getElementById('historyTotalStats');
  if(!weeklyC || !monthlyC || !totalC) return;

  if(trainingLog.length === 0){
    const empty = '<div class="log-empty">' + esc(t('noHistoryYet')) + '</div>';
    weeklyC.innerHTML = empty; monthlyC.innerHTML = empty; totalC.innerHTML = empty;
    return;
  }

  const weeks = {};
  const months = {};
  trainingLog.forEach(function(en){
    const d = new Date(en.dateISO);
    const ws = new Date(d); ws.setDate(d.getDate() - d.getDay());
    const wk = dayKey(ws);
    (weeks[wk] = weeks[wk] || []).push(en);
    const mk = d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0');
    (months[mk] = months[mk] || []).push(en);
  });

  function block(label, logs){
    const mins = logs.reduce(function(s,e){ return s + num(e.durationMin); }, 0);
    const cals = logs.reduce(function(s,e){ return s + num(e.calories); }, 0);
    const vol = logs.reduce(function(s,e){ return s + entryVolume(e); }, 0);
    return '<div style="padding:9px 10px; background:#1a1a1a; border-radius:8px; font-size:11px;">' +
      '<div style="font-weight:700; margin-bottom:4px;">' + esc(label) + '</div>' +
      '<div style="color:#9c9c9c;">' + esc(statLine(logs.length, mins, cals, vol)) + '</div></div>';
  }

  weeklyC.innerHTML = Object.keys(weeks).sort().reverse().slice(0, 12).map(function(wk){
    const d = new Date(wk + 'T12:00:00');
    const end = new Date(d); end.setDate(d.getDate()+6);
    const fmt = function(x){ return x.toLocaleDateString(currentLang === 'he' ? 'he-IL' : 'en-US', { day:'2-digit', month:'short' }); };
    return block(fmt(d) + ' – ' + fmt(end), weeks[wk]);
  }).join('');

  monthlyC.innerHTML = Object.keys(months).sort().reverse().slice(0, 12).map(function(mk){
    const parts = mk.split('-');
    return block(t('monthNames')[Number(parts[1])-1] + ' ' + parts[0], months[mk]);
  }).join('');

  const mins = trainingLog.reduce(function(s,e){ return s + num(e.durationMin); }, 0);
  const cals = trainingLog.reduce(function(s,e){ return s + num(e.calories); }, 0);
  const vol = trainingLog.reduce(function(s,e){ return s + entryVolume(e); }, 0);
  totalC.innerHTML =
    tile(trainingLog.length, t('workoutsUnit'), '#d7ff2b') +
    tile(mins, t('heroMinutesLabel'), '#3fd7e8') +
    tile(cals.toLocaleString(), t('calUnitShort'), '#e0c93f') +
    tile(vol.toLocaleString(), t('kgUnit'), '#ff9500');
}

function tile(value, label, color){
  return '<div class="hero-stat" style="background:#1a1a1a;">' +
    '<div style="font-size:18px; font-weight:800; color:' + color + ';">' + esc(String(value)) + '</div>' +
    '<div style="font-size:10px; color:#6f6f6f;">' + esc(label) + '</div></div>';
}

/* Minimal inline SVG line chart — no external library, CSP-safe. */
function lineChartSVG(points, color){
  if(points.length < 2) return '<div class="chart-empty">' + esc(t('noChartData')) + '</div>';
  const W = 320, H = 120, P = 22;
  const ys = points.map(function(p){ return p.v; });
  let min = Math.min.apply(null, ys), max = Math.max.apply(null, ys);
  if(max === min){ max = min + 1; min = Math.max(0, min - 1); }
  const x = function(i){ return P + (i/(points.length-1)) * (W - P*2); };
  const y = function(v){ return H - P - ((v-min)/(max-min)) * (H - P*2); };

  const path = points.map(function(p,i){ return (i ? 'L' : 'M') + x(i).toFixed(1) + ' ' + y(p.v).toFixed(1); }).join(' ');
  const dots = points.map(function(p,i){
    return '<circle cx="' + x(i).toFixed(1) + '" cy="' + y(p.v).toFixed(1) + '" r="2.5" fill="' + color + '"><title>' +
      esc(p.label + ': ' + p.v.toFixed(1)) + '</title></circle>';
  }).join('');

  return '<div style="direction:ltr;"><svg class="chart-svg" viewBox="0 0 ' + W + ' ' + H + '" role="img">' +
    '<line x1="' + P + '" y1="' + (H-P) + '" x2="' + (W-P) + '" y2="' + (H-P) + '" stroke="#333" stroke-width="1"/>' +
    '<path d="' + path + '" fill="none" stroke="' + color + '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>' +
    dots +
    '<text x="' + P + '" y="12" fill="#6f6f6f" font-size="9">' + max.toFixed(1) + '</text>' +
    '<text x="' + P + '" y="' + (H-P+12) + '" fill="#6f6f6f" font-size="9">' + min.toFixed(1) + '</text>' +
  '</svg></div>';
}

function renderProgress(){
  const sel = document.getElementById('progressExSelect');
  if(!sel) return;

  // exercise picker fed by everything ever logged plus the current program
  const names = {};
  exercises.forEach(function(ex){ names[ex.name] = true; });
  trainingLog.forEach(function(en){ (en.entries||[]).forEach(function(it){ names[it.name] = true; }); });
  const list = Object.keys(names);
  const prevSel = sel.value;
  sel.innerHTML = list.map(function(n){ return '<option value="' + esc(n) + '">' + esc(n) + '</option>'; }).join('');
  if(prevSel && list.indexOf(prevSel) !== -1) sel.value = prevSel;

  renderStrengthChart();
  renderBodyWeightChart();
  renderVolume();
}

function renderStrengthChart(){
  const c = document.getElementById('strengthChart');
  if(!c) return;
  const sel = document.getElementById('progressExSelect');
  const name = sel ? sel.value : '';
  if(!name){ c.innerHTML = '<div class="chart-empty">' + esc(t('noChartData')) + '</div>'; return; }

  const pts = [];
  trainingLog.slice().reverse().forEach(function(en){
    let best = 0;
    (en.entries||[]).forEach(function(it){
      if(it.name !== name) return;
      (it.sets||[]).forEach(function(s){ const v = e1rm(num(s.kg), num(s.reps)); if(v > best) best = v; });
    });
    if(best > 0) pts.push({ v: best, label: formatLogDate(en.dateISO) });
  });
  c.innerHTML = lineChartSVG(pts, '#d7ff2b');
}

function renderBodyWeightChart(){
  const c = document.getElementById('bodyWeightChart');
  if(!c) return;
  const pts = Object.keys(dailyLog).sort().filter(function(k){ return num(dailyLog[k].bodyKg) > 0; })
    .map(function(k){ return { v: num(dailyLog[k].bodyKg), label: k }; });
  c.innerHTML = lineChartSVG(pts, '#3fd7e8');
}

function renderVolume(){
  const c = document.getElementById('volumeContainer');
  if(!c) return;
  const since = new Date(); since.setDate(since.getDate()-7);
  const counts = {};
  MUSCLES.forEach(function(m){ counts[m] = 0; });
  trainingLog.forEach(function(en){
    if(new Date(en.dateISO) < since) return;
    (en.entries||[]).forEach(function(it){
      const m = MUSCLES.indexOf(it.muscle) !== -1 ? it.muscle : 'other';
      counts[m] += (it.sets||[]).length;
    });
  });
  const anySets = MUSCLES.some(function(m){ return counts[m] > 0; });
  if(!anySets){ c.innerHTML = '<div class="chart-empty">' + esc(t('noChartData')) + '</div>'; return; }

  c.innerHTML = MUSCLES.filter(function(m){ return m !== 'other' || counts[m] > 0; }).map(function(m){
    const n = counts[m];
    const cls = n === 0 || n < VOL_MIN ? 'low' : (n > VOL_MAX ? 'high' : 'ok');
    const pct = Math.min(100, (n / VOL_MAX) * 100);
    return '<div class="vol-row">' +
      '<div class="vol-name">' + esc(muscleLabel(m)) + '</div>' +
      '<div class="vol-track"><div class="vol-fill ' + cls + '" style="width:' + pct + '%;"></div></div>' +
      '<div class="vol-num">' + n + '</div>' +
    '</div>';
  }).join('');
}

/* ---------- 14. nutrition ---------- */
function toggleMealForm(show){
  document.getElementById('mealForm').classList.toggle('show', show);
  if(!show){
    editingMealIndex = null;
    ['mealName','mealCal','mealProtein','mealCarbs'].forEach(function(id){ document.getElementById(id).value = ''; });
  }
  updateFormLabels();
}

function saveMeal(){
  const name = document.getElementById('mealName').value.trim();
  if(!name){ flashToast(t('mealNameAlert')); return; }
  const payload = {
    name: name,
    tag: document.getElementById('mealTag').value,
    // Clamped for the same reason the exercise fields are: the global
    // keydown/input guard stops "-" from being typed, but a value that
    // arrives programmatically (paste, autofill) bypasses it.
    cal: Math.max(0, num(document.getElementById('mealCal').value)),
    protein: Math.max(0, num(document.getElementById('mealProtein').value)),
    carbs: Math.max(0, num(document.getElementById('mealCarbs').value))
  };
  const isEdit = editingMealIndex !== null;
  if(isEdit) meals[editingMealIndex] = payload; else meals.push(payload);
  saveKey('meals', meals);
  editingMealIndex = null;
  renderMeals();
  renderDashboardGoal();
  toggleMealForm(false);
  flashToast(isEdit ? t('mealUpdatedToast') : t('mealSavedToast'));
}

function editMeal(i){
  const m = meals[i];
  if(!m) return;
  editingMealIndex = i;
  document.getElementById('mealName').value = m.name || '';
  document.getElementById('mealTag').value = m.tag || 'breakfast';
  document.getElementById('mealCal').value = m.cal || '';
  document.getElementById('mealProtein').value = m.protein || '';
  document.getElementById('mealCarbs').value = m.carbs || '';
  const f = document.getElementById('mealForm');
  f.classList.add('show');
  updateFormLabels();
  f.scrollIntoView({ behavior:'smooth', block:'center' });
}

function deleteMeal(i){
  if(!meals[i]) return;
  meals.splice(i, 1);
  saveKey('meals', meals);
  if(editingMealIndex !== null) toggleMealForm(false);
  renderMeals();
  renderDashboardGoal();
  flashToast(t('mealDeletedToast'));
}

function renderMeals(){
  const c = document.getElementById('mealsList');
  if(!c) return;
  if(meals.length === 0){
    c.innerHTML = '<div class="log-empty">' + esc(t('mealsEmptyState')) + '</div>';
    renderNutritionSummary();
    return;
  }
  c.innerHTML = meals.map(function(m, i){
    return '<div class="meal-card">' +
      '<div class="meal-cal"><div class="meal-cal-num">' + num(m.cal) + '</div>' +
        '<div class="meal-cal-label">' + esc(t('calUnitLabel')) + '</div></div>' +
      '<div class="meal-info">' +
        '<span class="meal-tag">' + esc(displayMealTag(m)) + '</span>' +
        '<div class="meal-name">' + esc(displayMealName(m)) + '</div>' +
        '<div class="meal-meta">🔥 ' + num(m.protein) + esc(t('gramUnit')) + ' | 🌾 ' + num(m.carbs) + esc(t('gramUnit')) + '</div>' +
      '</div>' +
      '<div class="meal-thumb">' + (MEAL_TAG_EMOJI[m.tag] || '🍽️') + '</div>' +
      '<div class="card-actions">' +
        '<button class="icon-action" onclick="editMeal(' + i + ')" aria-label="' + esc(t('editAction')) + '">✎</button>' +
        '<button class="icon-action danger" onclick="deleteMeal(' + i + ')" aria-label="' + esc(t('deleteAction')) + '">🗑</button>' +
      '</div>' +
    '</div>';
  }).join('');
  renderNutritionSummary();
}

function renderNutritionSummary(){
  if(!metrics) return;
  const el = document.getElementById('sumCal');
  if(!el) return;
  const g = metrics.macroTarget;
  const totalCal = meals.reduce(function(s,m){ return s + num(m.cal); }, 0);
  const totalProt = meals.reduce(function(s,m){ return s + num(m.protein); }, 0);
  const totalCarb = meals.reduce(function(s,m){ return s + num(m.carbs); }, 0);
  const totalFat = Math.max(0, Math.round((totalCal - totalProt*4 - totalCarb*4)/9));
  const u = t('gramUnit');

  el.textContent = totalCal.toLocaleString() + ' / ' + g.calories.toLocaleString();
  document.getElementById('sumProt').textContent = totalProt + u + ' / ' + g.protein + u;
  document.getElementById('sumCarb').textContent = totalCarb + u + ' / ' + g.carbs + u;
  document.getElementById('sumFat').textContent = totalFat + u + ' / ' + g.fats + u;
  document.getElementById('sumCalBar').style.width = Math.min(100, totalCal/g.calories*100) + '%';
  document.getElementById('sumProtBar').style.width = Math.min(100, totalProt/g.protein*100) + '%';
  document.getElementById('sumCarbBar').style.width = Math.min(100, totalCarb/g.carbs*100) + '%';
  document.getElementById('sumFatBar').style.width = Math.min(100, totalFat/g.fats*100) + '%';
}

/* ---------- 15. camera vision — shared capture UI, two analysis targets ---------- */
let camStream = null;
let capturedDataUrl = null;
let visionMode = 'machine';   // 'machine' | 'food' — which endpoint/renderer analyzePhoto() uses

function openCamera(mode){
  visionMode = mode === 'food' ? 'food' : 'machine';
  capturedDataUrl = null;
  document.getElementById('visionResult').innerHTML = '';
  document.getElementById('camModalTitle').textContent =
    visionMode === 'food' ? t('cameraTitleFood') : t('cameraTitle');
  document.getElementById('camHint').textContent =
    visionMode === 'food' ? t('cameraHintFood') : t('cameraHint');
  document.getElementById('camModal').classList.add('show');
  updateCamButtons('idle');
}

/* The title/hint above are JS-managed (not data-i18n) because they depend on
   visionMode, not just language. Re-apply them on a language toggle so a
   still-open modal doesn't show stale-language text. */
function refreshCameraModalText(){
  const modal = document.getElementById('camModal');
  if(!modal || !modal.classList.contains('show')) return;
  document.getElementById('camModalTitle').textContent =
    visionMode === 'food' ? t('cameraTitleFood') : t('cameraTitle');
  document.getElementById('camHint').textContent =
    visionMode === 'food' ? t('cameraHintFood') : t('cameraHint');
}
function closeCamera(){
  stopCamStream();
  document.getElementById('camModal').classList.remove('show');
}
function stopCamStream(){
  if(camStream){ camStream.getTracks().forEach(function(tr){ tr.stop(); }); camStream = null; }
}
function updateCamButtons(mode){
  document.getElementById('camStartBtn').style.display = mode === 'idle' ? '' : 'none';
  document.getElementById('camShootBtn').style.display = mode === 'live' ? '' : 'none';
  document.getElementById('camRetakeBtn').style.display = mode === 'shot' ? '' : 'none';
  document.getElementById('camAnalyzeBtn').style.display = mode === 'shot' ? '' : 'none';
}

async function startCamera(){
  if(!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia){
    flashToast(t('cameraNoAccess')); return;
  }
  try {
    camStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
    const v = document.getElementById('camVideo');
    v.srcObject = camStream;
    v.style.display = '';
    document.getElementById('camShot').style.display = 'none';
    document.getElementById('camHint').style.display = 'none';
    await v.play();
    updateCamButtons('live');
  } catch(e){
    flashToast(t('cameraNoAccess'));
  }
}

function shootPhoto(){
  const v = document.getElementById('camVideo');
  if(!v.videoWidth) return;
  const canvas = document.createElement('canvas');
  const scale = Math.min(1, 1024 / v.videoWidth);
  canvas.width = Math.round(v.videoWidth * scale);
  canvas.height = Math.round(v.videoHeight * scale);
  canvas.getContext('2d').drawImage(v, 0, 0, canvas.width, canvas.height);
  capturedDataUrl = canvas.toDataURL('image/jpeg', 0.75);
  stopCamStream();
  v.style.display = 'none';
  const img = document.getElementById('camShot');
  img.src = capturedDataUrl;
  img.style.display = '';
  updateCamButtons('shot');
}

function retakePhoto(){
  capturedDataUrl = null;
  document.getElementById('camShot').style.display = 'none';
  document.getElementById('visionResult').innerHTML = '';
  startCamera();
}

/* Posts the photo to our own serverless endpoint. The API key lives on the
   server — never in this bundle. If the endpoint is absent or unconfigured we
   say so plainly rather than inventing a result. Which endpoint, which
   payload key marks success, and which renderer runs all follow visionMode —
   set once in openCamera() — so the capture/shutter/retake flow above is
   shared between the two analysis targets without duplication. */
async function analyzePhoto(){
  if(!capturedDataUrl) return;
  const out = document.getElementById('visionResult');
  out.innerHTML = '<div class="chart-empty">' + esc(t('cameraAnalyzing')) + '</div>';
  const isFood = visionMode === 'food';
  const endpoint = isFood ? '/api/analyze-food' : '/api/analyze-machine';
  const notConfiguredKey = isFood ? 'visionNotConfiguredFood' : 'visionNotConfigured';
  const failedKey = isFood ? 'visionFailedFood' : 'visionFailed';
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image: capturedDataUrl, lang: currentLang })
    });
    // 501 = key not set; 404/405 = deployed without a serverless runtime at all.
    if(res.status === 501 || res.status === 404 || res.status === 405){
      out.innerHTML = '<div class="vision-warn">' + esc(t(notConfiguredKey)) + '</div>';
      return;
    }
    if(!res.ok) throw new Error('http ' + res.status);
    const data = await res.json();
    if(!data || (isFood ? !data.food : !data.machine)) throw new Error('bad payload');
    if(isFood) renderFoodResult(data); else renderVisionResult(data);
  } catch(e){
    // Anything else is a real failure — say that, don't blame configuration.
    out.innerHTML = '<div class="vision-warn">' + esc(t(failedKey)) + '</div>';
  }
}

function renderVisionResult(data){
  const out = document.getElementById('visionResult');
  const exName = String(data.exercise || data.machine);
  out.innerHTML =
    '<div class="vision-result">' +
      '<h4>' + esc(data.machine) + '</h4>' +
      (data.muscle ? '<div><span class="tag muscle">' + esc(muscleLabel(data.muscle)) + '</span></div>' : '') +
      (data.howTo ? '<p style="margin-top:8px; color:#9c9c9c;">' + esc(data.howTo) + '</p>' : '') +
      (data.suggestion ? '<p style="margin-top:6px; color:#6f6f6f;">' + esc(data.suggestion) + '</p>' : '') +
      '<button class="btn btn-accent" style="margin-top:10px;" onclick="addVisionExercise(' +
        JSON.stringify(exName).replace(/"/g,'&quot;') + ',' +
        JSON.stringify(String(data.muscle || 'other')).replace(/"/g,'&quot;') + ')">' +
        esc(t('visionAddBtn')) + '</button>' +
    '</div>';
}

function addVisionExercise(name, muscle){
  if(exercises.some(function(e){ return e.name.toLowerCase() === String(name).toLowerCase(); })){
    flashToast(t('exerciseUpdatedToast'));
    closeCamera();
    return;
  }
  exercises.push({
    id: 'e' + Date.now().toString(36),
    name: name,
    tag: t('generalTag'),
    muscle: MUSCLES.indexOf(muscle) !== -1 ? muscle : 'other',
    sets: '3', reps: '10', targetKg: 0, restSec: settings.defaultRestSec
  });
  saveKey('exercises', exercises);
  renderExercises();
  renderHero();
  renderTemplateExPicker();
  closeCamera();
  flashToast(t('exerciseSavedToast'));
}

/* Food photo → estimated macros. The meal model only ever stored
   {name, tag, cal, protein, carbs} — manual entry has no fat field either,
   the daily summary derives fat from calories. Rather than widen that model
   for one entry path, show all four macros here for the user's benefit and
   push only the three that manual entry already saves; behaviour and storage
   stay identical to typing the same numbers in by hand. */
function renderFoodResult(data){
  const out = document.getElementById('visionResult');
  const cal = Math.max(0, num(data.calories));
  const protein = Math.max(0, num(data.protein));
  const carbs = Math.max(0, num(data.carbs));
  const fats = Math.max(0, num(data.fats));
  const tag = MEAL_TAG_KEYS[data.tag] ? data.tag : 'lunch';
  out.innerHTML =
    '<div class="vision-result">' +
      '<h4>' + esc(data.food) + '</h4>' +
      '<div class="grid-4" style="margin-top:10px;">' +
        tile(cal, t('calUnitLabel'), '#d7ff2b') +
        tile(protein + t('gramUnit'), t('macroProtein'), '#3fd7e8') +
        tile(carbs + t('gramUnit'), t('macroCarbs'), '#e0c93f') +
        tile(fats + t('gramUnit'), t('macroFats'), '#ff9500') +
      '</div>' +
      (data.notes ? '<p style="margin-top:10px; color:#9c9c9c; font-size:11px; line-height:1.5;">' + esc(data.notes) + '</p>' : '') +
      '<button class="btn btn-accent" style="margin-top:10px;" onclick="fillMealFromVision(' +
        JSON.stringify(String(data.food)).replace(/"/g,'&quot;') + ',' +
        JSON.stringify(tag).replace(/"/g,'&quot;') + ',' + cal + ',' + protein + ',' + carbs +
      ')">' + esc(t('visionUseBtn')) + '</button>' +
    '</div>';
}

function fillMealFromVision(name, tag, cal, protein, carbs){
  closeCamera();
  switchScreen('nutrition');
  editingMealIndex = null;
  toggleMealForm(true);
  document.getElementById('mealName').value = name;
  document.getElementById('mealTag').value = MEAL_TAG_KEYS[tag] ? tag : 'lunch';
  document.getElementById('mealCal').value = Math.max(0, num(cal));
  document.getElementById('mealProtein').value = Math.max(0, num(protein));
  document.getElementById('mealCarbs').value = Math.max(0, num(carbs));
  updateFormLabels();
  const f = document.getElementById('mealForm');
  f.scrollIntoView({ behavior: 'smooth', block: 'center' });
  flashToast(t('mealFilledFromPhotoToast'));
}

/* ---------- 16. plate calculator ---------- */
const PLATE_SIZES = [25, 20, 15, 10, 5, 2.5, 1.25];
const PLATE_COLORS = { 25:'#ff6b6b', 20:'#3fd7e8', 15:'#e0c93f', 10:'#7ee787', 5:'#f2f2f2', 2.5:'#9c9c9c', 1.25:'#6f6f6f' };

function openPlateCalc(){
  document.getElementById('plateModal').classList.add('show');
  document.getElementById('plateBarInput').value = settings.barKg || 20;
  calcPlates();
}
function closePlateCalc(){ document.getElementById('plateModal').classList.remove('show'); }

function calcPlates(){
  const target = num(document.getElementById('plateTargetInput').value);
  const bar = num(document.getElementById('plateBarInput').value);
  settings.barKg = bar;
  saveKey('settings', settings);

  const out = document.getElementById('plateResult');
  const perSide = (target - bar) / 2;
  if(!target || perSide <= 0){ out.innerHTML = '<div class="plate-empty">—</div>'; return; }

  let left = perSide;
  const used = [];
  PLATE_SIZES.forEach(function(p){
    while(left >= p - 0.001){ used.push(p); left -= p; }
  });
  const exact = left < 0.01;

  out.innerHTML =
    '<div class="plate-vis">' +
      '<div class="plate-bar"></div>' +
      used.map(function(p){
        const h = 22 + p;
        return '<div class="plate" style="height:' + h + 'px; background:' + PLATE_COLORS[p] + ';">' + p + '</div>';
      }).join('') +
    '</div>' +
    '<div style="text-align:center; font-size:12px; color:#9c9c9c;">' +
      esc(t('plateResult')) + ': ' + (used.length ? used.join(' + ') : '—') + ' ' + esc(t('kgUnit')) +
    '</div>' +
    (exact ? '' : '<div class="vision-warn">' + esc(t('plateImpossible')) + '</div>');
}

/* ---------- 17. export / import ---------- */
function exportData(){
  const payload = {
    _format: 'fitpro-backup', _version: 2, exportedAt: new Date().toISOString(),
    profileName: (profiles.find(function(p){ return p.id === activeProfileId; }) || {}).name || '',
    user:user, metrics:metrics, meals:meals, exercises:exercises,
    trainingLog:trainingLog, dailyLog:dailyLog, templates:templates,
    trainingDays:trainingDays, settings:settings
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type:'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'fitpro-backup-' + todayKey() + '.json';
  document.body.appendChild(a); a.click(); document.body.removeChild(a);
  setTimeout(function(){ URL.revokeObjectURL(url); }, 1000);
  flashToast(t('exportedToast'));
}

function triggerImport(){ document.getElementById('importFile').click(); }

function importData(input){
  const file = input.files && input.files[0];
  if(!file) return;
  const reader = new FileReader();
  reader.onload = function(){
    let data;
    try { data = JSON.parse(reader.result); }
    catch(e){ flashToast(t('importFailed')); input.value = ''; return; }
    if(!data || data._format !== 'fitpro-backup'){ flashToast(t('importFailed')); input.value = ''; return; }
    if(!confirm(t('importConfirm'))){ input.value = ''; return; }

    user = data.user || null;
    metrics = data.metrics || null;
    meals = data.meals || [];
    exercises = data.exercises || [];
    trainingLog = data.trainingLog || [];
    dailyLog = data.dailyLog || {};
    templates = data.templates || [];
    trainingDays = data.trainingDays || [false,false,false,false,false,false,false];
    settings = data.settings || settings;

    const toPersist = {
      user:user, metrics:metrics, meals:meals, exercises:exercises, trainingLog:trainingLog,
      dailyLog:dailyLog, templates:templates, trainingDays:trainingDays, settings:settings
    };
    Object.keys(toPersist).forEach(function(k){ saveKey(k, toPersist[k]); });

    migrateShapes();
    input.value = '';
    if(user && metrics){ enterApp(true); flashToast(t('importedToast')); }
    else flashToast(t('importFailed'));
  };
  reader.readAsText(file);
}

/* ---------- toast ---------- */
let toastTimer;
function flashToast(msg){
  const el = document.getElementById('saveToast');
  if(!el) return;
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function(){ el.classList.remove('show'); }, 2200);
}

/* ---------- 18. boot ---------- */
/* No figure in this app is ever meaningfully negative — not sets, reps, load,
   rest, sleep, steps, body weight or calories. type="number" does not stop a
   "-" being typed (min/max are only enforced on <form> submit, and none of
   these inputs live in a form), so block the sign at the keyboard and strip it
   from anything pasted or spun in. Delegated, so it covers the set rows that
   are rendered during a workout. */
const SIGN_KEYS = ['-', '+', 'e', 'E'];
document.addEventListener('keydown', function(e){
  const el = e.target;
  if(!el || el.type !== 'number') return;
  if(e.ctrlKey || e.metaKey || e.altKey) return;   // leave Ctrl/Cmd+- (zoom) alone
  if(SIGN_KEYS.indexOf(e.key) !== -1) e.preventDefault();
}, true);

document.addEventListener('input', function(e){
  const el = e.target;
  if(!el || el.type !== 'number') return;
  if(el.value.indexOf('-') === -1) return;
  const cleaned = el.value.replace(/-/g, '');
  el.value = cleaned;
  // Re-run the field's own handler so state matches what is now displayed.
  el.dispatchEvent(new Event('change', { bubbles: true }));
}, true);

document.addEventListener('keydown', function(e){
  if(e.key !== 'Escape') return;
  closeSidebar();
  ['profileModal','plateModal','camModal','sessionExModal'].forEach(function(id){
    const m = document.getElementById(id);
    if(m && m.classList.contains('show')){
      m.classList.remove('show');
      if(id === 'camModal') stopCamStream();
    }
  });
});

function registerSW(){
  if(!('serviceWorker' in navigator)) return;
  if(location.protocol !== 'http:' && location.protocol !== 'https:') return;
  navigator.serviceWorker.register('sw.js').catch(function(){ /* offline support is optional */ });
}

function init(){
  applyLanguage(loadGlobal('lang', 'he'));
  migrateToProfiles();

  if(activeProfileId){
    loadProfileData();
    applyLanguage(currentLang);
    if(user && metrics){
      const hadWorkout = workoutSeconds > 0 || session.entries.length > 0;
      enterApp(true);
      if(hadWorkout) flashToast(t('workoutRestoredToast'));
      registerSW();
      return;
    }
  }
  calcMacros();
  registerSW();
}

init();
