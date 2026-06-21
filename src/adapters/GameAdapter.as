interface GameAdapter
{
    GameObservation@ Observe();
}

GameAdapter@ CreateGameAdapter()
{
#if TMNEXT
    return NextGameAdapter();
#elif TURBO
    return TurboGameAdapter();
#else
    return null;
#endif
}

string AdapterGameName()
{
#if TMNEXT
    return "trackmaniaNext";
#else
    return "trackmaniaTurbo";
#endif
}
