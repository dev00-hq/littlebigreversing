# Resurrecting Crimsonland

Decompiling and preserving a cult 2003 classic game

Author

banteg

Published

February 1, 2026

some games die quietly. they get delisted, lose their multiplayer servers, fade into the digital void. others get remastered by the original authors with slightly better graphics and a battle pass.

and then there’s the third way: you open the binary in ghidra and start naming functions.

## the history

**crimsonland** (2003, remastered 2014, resurrected 2026) is a top-down shooter from the era when indie games were still called “shareware” and steam was something that came out of radiators. you play as a small man with a gun. things try to touch you. you shoot them. eventually there are too many things. you die. it’s perfect.

i remember vividly downloading it on a 56k modem and playing with a friend. the tiny 7.5mb game had us entertained for months. it was the first game by a finnish studio 10tons. they initially made a free game in 2002. i preserved a few of those early freeware versions:

[v1.0.2](https://paq.crimson.banteg.xyz/freeware/crimsonland_v1.0.2.zip) from may 2002 is an early prototype that establishes core mechanics.

[v1.3.0](https://paq.crimson.banteg.xyz/freeware/crimsonland_v1.3.0.zip) from july 2002 adds 3 music tracks not heard later in the shareware version. you can listen to them [here](https://soundcloud.com/slepoy/sets/crimsonland-ost) as tracks 10-12.

[v1.4.0](https://paq.crimson.banteg.xyz/freeware/crimsonland_v1.4.0.zip) from september 2002 is the final free version before 10tons heard the big news: the game got picked up by reflexive arcade, a major publisher at the time. the shareware version has seen release in april 2003 and it has spread like wildfire, including cover CDs of various game magazines.

the shareware version is known as v1.8.x-1.9.x series, with v1.9.8 from september 2003 receiving a cult following for some of the most overpowered combos possible of all versions. after reflexive shut down in 2010, there was another update v1.9.93 that has added widescreen support (960x800). the very same version has later become a free bonus on [gog.com](https://www.gog.com/en/game/crimsonland) when the studio has made a remaster in 2014.

but let’s not get ahead of ourselves. the game got a cult following, the studio was teasing crimsonland 2 with features like network multiplayer and a fully rewritten engine. this archived blog [page](https://web.archive.org/web/20140810035045/http://legacy.crimsonland.com/?menu=news_2005_2007) is the most representative of the sequel hopium. the forum was swarming with theories and excitement. here are some of the concepts that were posted ([source](https://web.archive.org/web/20081025021405/http://www.10tons.org/crimsonforum/viewtopic.php?id=69)):

by 2010 it was clear that crimsonland 2 was not going to happen. the studio has long shifted their focus to casual mobile games (infinite money glitch) that look more like zuma deluxe rather than their first game.

in 2013 the studio floats a remaster idea via steam greenlight, and the game sees a steam release on june 11, 2014. a gog.com release came a month later, and osx (now macos), linux, ps4, xbox releases have followed.

![](https://banteg.xyz/posts/crimsonland/cl2003-menu.avif)

*crimsonland 2003*

![](https://banteg.xyz/posts/crimsonland/cl2014-menu.avif)

*crimsonland 2014*

the game has its fans, but my heart lies there, in 2003, with the original mechanics.

## the project

not gonna lie, i was interested in understanding what makes this game tick at a deeper level for a long time. i tried decompiling it, i came back to making clones decades apart. something about it was alluring.

by the time i started this project on january 16, 2026, i had a pretty good understanding of things like the custom formats the game uses. i could unpack and repack assets.

in my previous attempt around start of 2025 i loaded it in binary ninja and went back and forth with llms to gradually rename functions. this works for about three hours, then you start questioning your career choices.

now i could partially automate the loop with coding agents that never get tired, and if i set it up well enough, hopefully the errors won’t snowball. for this project i used codex with gpt-5.2 exclusively, as i found it to be the most rigorous agentic model.

about 4 days into the decompile and 653 commits in i finally understood my goal.

not a spiritual successor. not a modernization. not “inspired by.”

the goal is a complete rewrite that matches the original windows binary behavior exactly. if the original has a bug, the rewrite has the same bug. if there’s a texture that’s one pixel too small (there is), i replicate that too. the executable is the spec, and we’re writing the spec back into source code.

three rules:

1. full fidelity. all behavior must match the gog classic build (v1.9.93, built february 2011). this is our specimen.
2. no guessing. every reimplemented function must trace back to decompiled code or runtime evidence. when the decompiler lies, i instrument the running binary.
3. no dependencies on the original runtime. assets load from the original archives, but all code is written from scratch.

## the patient

the version of `crimsonland.exe` we are working with is a directx 8.1 game built in visual studio 2003 (vc++ 7.1 sp1). the binary has zero information that is helpful for reverse engineering it. it also comes with `grim.dll`, which is the game engine (grim2d). the remaster uses a different engine. i found `NX` symbols in the linux remaster (unstripped!), so i think it’s called nexus.

the binary is fascinatingly naked. 378kb of uninitialized data in the `.data` section. no names or types preserved for us to rely on. for the first ~800 commits i was just shooting in the dark.

the more i was looking at the game, this time capsule of early-2000s game architecture, the more i understood that i wouldn’t get any help. there were no lua scripts and everything was hardcoded in the exe.

so our starting point is missing names + missing types + missing calling conventions + c++/com indirection courtesy of directx 8 and grim.dll. everything is “object pointer → vtable → function pointer call”. the usual decompiler output looked somewhat like this:

```
(**(code **)(*(int *)this + 0x114))(this, ...)
```

the rendering engine lives in `grim.dll`, a separate binary that exports just one function: `GRIM__GetInterface`. this hands you a pointer to an 84-method vtable wrapping direct3d 8, directinput, and a custom 2d sprite renderer. you don’t call direct3d. you call `grim->BindTexture()`, `grim->DrawQuad()`. everything is indirect.

that vtable becomes a rosetta stone. map entry `0x114` to `set_color(r,g,b,a)` and suddenly you can interpret some draw sequences. record runtime calls and compare them to your rewrite.

i needed a good setup to illuminate the path.

![](https://banteg.xyz/posts/crimsonland/vtable1.avif)

*the biggest unlock in mapping vtables*

## static analysis

there are two different ways to study an executable: static analysis and runtime analysis. i used both in this project extensively.

for static analysis there are basically three heavyweights:

- ida pro, the oldest and the most expensive, but offers the highest quality decompile for that era.
- binary ninja, often just called binja, also paid and quite featureful. it supports multi-level disassembly going from assembly to high-level intermediate language and pseudo rust. binja is easily scriptable with python.
- ghidra, which is completely free and also quite scriptable with java. it’s the easiest to run in headless mode.

### ghidra

i set up ghidra in a devcontainer and started shaping up the pipeline. within hours i had a 101,412 line long decompile with raw names like `FUN_00430af0` and `DAT_0049bf74`. since im only interested in the game logic, the logical first step is to eliminate the embedded [third-party libraries](https://crimson.banteg.xyz/third-party-libs/). `grim.dll` statically linked libpng, libjpeg, zlib. it was often possible to identify the right versions from things like `png_create_read_struct("1.0.5", ...)`, `deflate 1.1.3`, provide the appropriate headers, so ghidra could recognize their structs.

on day 1 i started a `name_map.json`, where i documented all the function renames and types i identified so far. since each rename was only our guess, it was important to document our logic. behavior observed to name inferred. string literals, call patterns, struct sizes, and relationships to already-named functions all serve as evidence.

for example, our agent observes that a function searches existing entry by name, allocates a 0x24 entry when missing, strdup’s name/value, parses float via crt_atof_l, and is used by register_core_cvars with “cv_*” strings. it renames `FUN_00402350` to `console_register_cvar` and adds an entry to our map.

```
{
  "program": "crimsonland.exe",
  "address": "0x00402350",
  "name": "console_register_cvar",
  "signature": "void * console_register_cvar(char *name, char *value)",
  "comment": "registers or updates a console cvar entry (stores string + float value)"
},
```

on the next regen more types will propagate. then you repeat it 300 more times and confidently map around 2000 functions and labels we care about. you can see more in my [detangling notes](https://crimson.banteg.xyz/detangling/).

![](https://banteg.xyz/posts/crimsonland/ghidra1.avif)

*the joy of renaming*

if you look at the decompile today, you may notice it has grown by 13,000 lines to 114,473 lines. this is because ghidra initially has missed quite a large chunk of functions, most notably game initialization.

there was also some deliberately obfuscated functions like the credit secret sequence, where i needed to capture the right entrypoint at runtime and manually create a function at that address.

by day 5 i had a pretty good idea of game structs and the engine vtable layout. so i added header files for `IGrim2D.h` and `crimsonland_types.h`. later i have found that some versions of the game have shipped with `cl_mod_sdk_v1` that had some headers, but it was not extremely helpful because i found it when the project was already in an advanced phase.

seeing steady progress was motivating. i set up a knowledge base (with [zensical](https://zensical.org/docs/get-started/)) on day one and was mapping whatever patterns codex had high confidence in. here is an example of what i started with and what it looks like now. and it gets more readable with each iteration.

- 1 day in
- 16 days in

```
/* FUN_00444980 @ 00444980 */
void __cdecl FUN_00444980(char param_1,char param_2)
{
    // ...
    if (fVar2 < 0.0) {
      (&DAT_00490bac)[iVar6 * 0xd8] = 0;
    }
    (&DAT_00490b84)[iVar6 * 0xd8] = 0;
    *(undefined4 *)(&DAT_004908cc + iVar7) = 0;
    *(undefined4 *)(&DAT_004908d0 + iVar7) = 0;
    (&DAT_00490b68)[iVar6 * 0xd8] = 0;
    (&DAT_00490b7c)[iVar6 * 0xd8] = (&DAT_00490b74)[iVar6 * 0xd8];
    (&DAT_00490b80)[iVar6 * 0xd8] = 0;
    if (param_2 != '\0') {
      FUN_00413430();
      iVar6 = DAT_004aaf0c;
    }
    bVar3 = false;
    (&DAT_00490900)[iVar6 * 0xd8] = *unaff_retaddr;
    (&DAT_00490904)[iVar6 * 0xd8] = unaff_retaddr[1];
    fVar9 = (float10)fpatan((float10)(float)(&DAT_004908c8)[iVar6 * 0xd8] -
                            (float10)(float)(&DAT_00490904)[iVar6 * 0xd8],
                            (float10)(float)(&DAT_004908c4)[iVar6 * 0xd8] -
                            (float10)(float)(&DAT_00490900)[iVar6 * 0xd8]);
    (&DAT_00490bb0)[iVar6 * 0xd8] = (float)(fVar9 - (float10)1.5707964);
    if (((float)(&DAT_00490b84)[iVar6 * 0xd8] <= 0.0) &&
       ((float)(&DAT_00490b80)[iVar6 * 0xd8] == 0.0)) {
      bVar3 = true;
      (&DAT_00490b78)[iVar6 * 0x360] = 0;
    }
    bVar4 = false;
    if ((((float)(&DAT_00490b84)[iVar6 * 0xd8] <= 0.0) &&
        (0 < (int)(&DAT_0049095c)[iVar6 * 0xd8])) &&
       ((iVar6 = perk_count_get(DAT_004c2bd0), iVar6 != 0 ||
           (iVar7 = perk_count_get(DAT_004c2bc8), iVar6 = DAT_004aaf0c, bVar4 = false, iVar7 != 0)))
       ) {
      bVar4 = true;
      iVar6 = DAT_004aaf0c;
    }
    // ...
```

```
/* player_fire_weapon @ 00444980 */
void __cdecl player_fire_weapon(char param_1,char param_2)
{
    // ...
    fVar2 = (&player_state_table)[render_overlay_player_index].muzzle_flash_alpha -
            (frame_dt + frame_dt);
    (&player_state_table)[render_overlay_player_index].muzzle_flash_alpha = fVar2;
    if (fVar2 < 0.0) {
      (&player_state_table)[iVar5].muzzle_flash_alpha = 0.0;
    }
    (&player_state_table)[iVar5].shot_cooldown = 0.0;
    (&player_state_table)[iVar5].move_dx = 0.0;
    (&player_state_table)[iVar5].move_dy = 0.0;
    (&player_state_table)[iVar5].spread_heat = 0.0;
    (&player_state_table)[iVar5].ammo = (&player_state_table)[iVar5].clip_size;
    (&player_state_table)[iVar5].reload_timer = 0.0;
    if (param_2 != '\0') {
      player_start_reload();
      iVar5 = render_overlay_player_index;
    }
    bVar3 = false;
    (&player_state_table)[iVar5].aim_x = *unaff_retaddr;
    (&player_state_table)[iVar5].aim_y = unaff_retaddr[1];
    fVar8 = (float10)fpatan((float10)(&player_state_table)[iVar5].pos_y -
                            (float10)(&player_state_table)[iVar5].aim_y,
                            (float10)(&player_state_table)[iVar5].pos_x -
                            (float10)(&player_state_table)[iVar5].aim_x);
    (&player_state_table)[iVar5].aim_heading = (float)(fVar8 - (float10)1.5707964);
    if (((&player_state_table)[iVar5].shot_cooldown <= 0.0) &&
       ((&player_state_table)[iVar5].reload_timer == 0.0)) {
      bVar3 = true;
      *(undefined1 *)&(&player_state_table)[iVar5].reload_active = 0;
    }
    bVar4 = false;
    if ((((&player_state_table)[iVar5].shot_cooldown <= 0.0) &&
        (0 < (&player_state_table)[iVar5].experience)) &&
       ((iVar5 = perk_count_get(perk_id_regression_bullets), iVar5 != 0 ||
        (iVar6 = perk_count_get(perk_id_ammunition_within), iVar5 = render_overlay_player_index,
        bVar4 = false, iVar6 != 0)))) {
      bVar4 = true;
      iVar5 = render_overlay_player_index;
    }
    // ...
```

### binary ninja

binary ninja only has headless mode in the more expensive version i don’t have. in my version i could use [binary_ninja_mcp](https://github.com/fosdickio/binary_ninja_mcp) and connect the agents to it. honestly they love it, and it allows for far more fluid automatic exploration than grepping through a 100k line ghidra decompile. they can easily ask the mcp questions like “what calls this?”, “what references this?”, “show me decompile of this function”, “find functions matching a pattern”.

it can also be used for retyping and renaming, but in my case the source of truth comes from my ghidra maps, which i apply to regen the binja outputs, so i ended up not using this functionality.

## runtime analysis

static analysis is at best a hypothesis. i needed a way to validate in runtime. the game runs in wine (poorly), but the translation could look as ridiculous as this. we wouldn’t be capturing useful information after going through so many layers.

> D3D8 → dgVoodoo → D3D11 → DXVK → Vulkan → MoltenVK → Metal

the truth is, it’s easiest to debug a windows game on windows. first i set up a vm using utm. it was a bit too slow for me to enjoy the project, so i bit the bullet and installed windows on my old macbook using bootcamp.

for runtime analysis i tried a bunch of things, many of them were a dead end. im looking at you, x86dbg, literally the most useless and frustrating program i ever interacted with and i got nowhere with it.

after a lot of trial and error i got two complementary tools working:

### windbg

this is microsoft’s own debugger, it comes with a cli tool called `cdb` that shares the same engine. a cli tool is always nice, because it promises us headless analysis and agentic loops working.

cdb can connect to a running process and set breakpoints, read memory, inspect callstacks, all the usual stuff. combined with our data map, it becomes a very powerful extension to speed up the ghidra mapping process.

i tried setting it up with codex with `cdb -pn crimsonland.exe`. it should be noted that codex runs subprocesses in a pty, so it can talk to them both ways interactively. the only problem is it’s hardwired in a way that it kills the process when it ends the turn and gives you an answer. so you can’t really talk to codex while it sets breakpoints and watchers. of course, codex is open source and you can fork it and patch this behavior, but i found a different solution that works about as reliably.

cdb supports a server/client mode, so you can set this up using a long-running server process that attaches to the process that you start and a couple of commands for your agent. i use a justfile so it just needs to know the shortcuts. the client persists no logs, so we need the server to log into an external file. finally, there is a tiny helper script that remembers the position we have read the file last time and outputs the tail, so the agent can inspect the logs as it was receiving them live.

```
windbg-server:
    cdb -server tcp:port=5005,password=secret -logo C:\windbg.log -pn crimsonland.exe -noio

windbg-client:
    cdb -remote tcp:server=127.0.0.1,port=5005,password=secret -bonc

windbg-tail:
    uv run scripts/windbg_tail.py
```

this setup allows interactive windbg sessions.

![](https://banteg.xyz/posts/crimsonland/cdb1.avif)

*codex controlling windbg using `cdb -remote`*

### frida

another tool i use extensively is called frida (`uv tool install frida-tools`). it allows injecting javascript into a running process. frida can hook functions, trace calls, modify arguments and return values on the fly.

the scripts can get very advanced. for example, i was having trouble with replicating the ground rendering exactly. as i understood later, it was caused by different default conventions between directx8 and opengl. i used frida to capture and save a framebuffer from the game to use it as a test fixture for my renderer.

other useful things possible with frida include different debug style shortcuts like cycling weapons, as well as capturing runtime logs to confirm your hypotheses.

to attach a frida script to a running process, you simply do:

```
frida -n crimsonland.exe -l scripts\frida\unlock_secrets.js
```

## the formats

with any game project you want to start from understanding the custom formats it uses. i was curious about this game before, so i had some understanding already.

crimsonland ships its assets in **paq** files, which is a custom archive format with a four-byte magic (`paq\0`), then a stream of entries: null-terminated filename, little-endian size, raw bytes. the paths are windows-style with backslashes.

i have used a very good python library called construct that allows to define such formats declaratively.

```
from construct import Bytes, Const, CString, GreedyRange, Int32ul, Struct

MAGIC = b"paq\x00"

PAQ_ENTRY = Struct(
    "name" / CString("utf8"),
    "size" / Int32ul,
    "payload" / Bytes(lambda ctx: ctx.size),
)

PAQ = Struct(
    "magic" / Const(MAGIC),
    "entries" / GreedyRange(PAQ_ENTRY),
)
```

inside the paqs are textures in **jaz** format, which is where things get architecturally interesting. it was previously known that jaz is a zlib compressed jpg with some unknown data attached to it.

im happy to announce that codex has understood the meaning of the unknown section in two hours, and has solved something that had previously got me puzzled for days. turns out jaz takes a jpg and wraps it with a custom run length encoded alpha channel, then compresses the whole thing again with zlib. here is a couple of textures extracted with the correct alpha.

![](https://banteg.xyz/posts/crimsonland/alien.avif)

*game\alien.jaz*

![](https://banteg.xyz/posts/crimsonland/spider_sp1.avif)

*game\spider_sp1.jaz*

the alpha rle expands to `width * height` bytes. most assets match exactly. interestingly one file is short by exactly one pixel.

i have construct parsers for both formats. `uv run paq extract crimsonland/ assets/` dumps everything, converting jaz to png.

## text rendering

by the moment you have firmly decided on a from scratch rewrite, the next good thing to understand and implement is text rendering. it will unlock debug views and you are going to need a lot of them before all the systems are wired up together.

![](https://banteg.xyz/posts/crimsonland/fonts0.avif)

*all your fonts are belong to us*

by now i have a full understanding of where all fonts in the game come from, so technically we can bolt on vector text rendering later. finding the fonts was a funny exercise on its own, you really need to get into the dev’s head. what was he thinking? ah yes, dafont.com.

the identified fonts are xirod regular for the crimsonland logo (with a flipped m), armor piercing regular for the menu labels, pixel arial 11 for the small text, courier new bold for level names.

i eyeballed the pixel font as arial but later was able to find the exact variant used in the game. this finding allows us to either use normal arial or this pixel font and sidestep noticeable jpeg compression artifacts from the game version sprite atlas.

![](https://banteg.xyz/posts/crimsonland/fonts1.avif)

*possible upgrade paths for small font*

## choosing the engine

since i was rewriting the game from scratch, i needed to iterate quickly. so i chose to have a reference intermediate implementation that i could test and refactor easily, before rewriting to something more performant. it was important to me to capture the game logic in a readable way, not just make the game compile on modern systems.

choosing the right engine is extremely important so i spent an entire day going through the options. modern engines tend to abstract things too much with concepts like actors and such. it’s a completely different paradigm from what the game did. directx 8 uses a very direct rendering approach. so we needed something barebones to replicate that. i ultimately chose [raylib](https://www.raylib.com/) for my rewrite. so far im happy with the choice.

the engine handles things like creating a game window, drawing textures, playing sounds, streaming music, and handling input. so basically it takes care of some of the stuff `grim.dll` does. the only thing left to do is to fill in the entire game.

## the rewrite

up to this point i was greedily documenting every behavior we could infer from the executable, but we had no code of our own besides the format loaders.

i think of it like getting a noisy picture in path tracing rendering. some details start to come through but the picture is not fully clear yet. we have random things documented but we can’t know for sure if this knowledge is sufficient to reimplement the entire game. there is only one way to know.

we need to change our render settings to scanline. just kidding, but that’s how i thought about it. when my version could boot into the menu, we would have uncovered all the missing pieces that lead up to that point. when we get to the gameplay, we’d have to implement the most systems to get there. our documentation helps, but this forward path leaves no system untouched and eventually we have our working game.

on day 6, when i got to the main menu, i found a funny path that would allow me to cover a lot of ground. i noticed the game still had demo teaser code intact, but `game_is_full_version()` was hardcoded to 1 in this gog version. naturally, i could write a frida script to *uncrack* the game and make it behave like a shareware, even though this version never intended such functionality.

the rendering in this game is pretty simple. there is a ground framebuffer (in opengl, i believe, the correct term is render target). first the game generates a terrain, i went great to lengths to get it right. we literally have test fixtures that assert we generate the exact same picture from the same seed. then this framebuffer is used to render all sorts of decals, like bodies, blood, bullet casings, scorch marks. this simple technique allows the game to visually transform the battlefield during gameplay.

the creatures come from sprite atlases you’ve seen above. the projectiles render with either beautiful traces that stay in the air, or at most with a simple texture and additive glow.

so rendering was not a huge obstacle, the hard part was that everything in this game is hardcoded in the exe. for example, all quest spawn scenarios are just one massive 3950 line switch statement. the indirection i mentioned has caused me a bunch of headaches, and i hit off-by-one errors for some things a few times, before they got pinned down with runtime analysis.

obviously, i needed our version more testable, so some of it was destined to be refactored into composable and testable bits. testing is important, because you can turn runtime captures into fixtures, and prove that your behavior is identical. for example, this is how quest builders look in my version (and spawn templates are another work of art).

```
@register_quest(
    level="2.5",
    title="Sweep Stakes",
    time_limit_ms=35000,
    start_weapon_id=6,
    unlock_perk_id=PerkId.BARREL_GREASER,
)
def build_2_5_sweep_stakes(ctx: QuestContext, rng: random.Random | None = None) -> list[SpawnEntry]:
    rng = rng or random.Random()
    entries: list[SpawnEntry] = []
    center_x, center_y = center_point(ctx.width, ctx.height)
    trigger = 2000
    step = 2000
    while step > 720:
        angle = random_angle(rng)
        for x, y in radial_points(center_x, center_y, angle, 0x54, 0xFC, 0x2A):
            heading = heading_from_center(x, y, center_x, center_y)
            entries.append(
                spawn(
                    x=x,
                    y=y,
                    heading=heading,
                    spawn_id=SpawnId.ALIEN_AI7_ORBITER_36,
                    trigger_ms=trigger,
                    count=1,
                )
            )
        trigger += max(step, 600)
        step -= 0x50
    return entries
```

some things are harder to test, but we’ll eventually get there, as refactors are free in the agentic era.

some things are outright wild programming choices, but understandable given it’s this studio’s first game. one particularly memorable example is negative hitbox sizes driving animation frames.

over time we moved from stochastic noise of understanding the assembly to the scanline precision of making it run.

## current status

46,800 lines of code, 16,000 lines of documentation.

the gameplay is fully wired up, all game modes are playable end to end, all weapons do work, as do all perks. some logic bugs still persist, and there are some gaps in non-gameplay things, like credits and the hidden alien zoo keeper game.

the end goal is a working and thoroughly documented reimplementation. one that a seasoned crimsonland player wouldn’t be able to tell from the original game. i am very close to that goal.

parity with a decompiled binary may sound like a strange goal. you can’t just make it *look* right. you have to make it *be* right. as someone ominously joked in an x reply, with 90% of work done, the other 90% of chasing bugs and imperfections remain.

## what’s next

after the core game is done, we can perhaps resurrect online high scores, or even try to tackle harder things like network multiplayer, promised to us in crimsonland 2.

i specifically didn’t want any graphical enhancements, as my goal was to preserve a childhood memory exactly as i remember it. for people who want a remake, there was already one made in 2014. if someone wants to port the original crimsonland in 2040, they can start with what i have mapped. this game is a lightning in the bottle and it deserves to outlive its original build.

one day i dreamt one enhancement up that i find very fitting. what if we keep everything exactly the same, but add a night mode with an ultra quality lighting. muzzle flash will cast long shadows, and there are plenty emissive projectiles in the game, like plasma (both trooper’s and spider’s), ion weapons, rocket launchers, and nukes.

i immediately researched the most fitting algorithm and implemented [soft shadows in raymarched signed distance fields](https://iquilezles.org/articles/rmshadows/), so we can have long soft shadows with realistic penumbras. it works really well too, i might integrate it into the game as an optional night mode.

![](https://banteg.xyz/posts/crimsonland/sdf1.avif)

*an early prototype of signed distance field raymarched lighting*

## the implications

in 2014, it took a year to port the game from directx 8 to directx 11, while having the sources. and it wasn’t even complete until later, some modes like typ-o-shooter landed as updates later on.

> it took us a bit more than a year from the old windows version from 2003 to the current multiplatform version of crimsonland. – 10tons

in 2026, it took me just two weeks and 1666 commits to rewrite the game, starting from nothing but the worst case scenario binaries. the whole time i saw steady progress every day, i didn’t get stuck, the errors didn’t snowball, and the game is actually playable and faithful to the original.

i specifically picked a task that is on the harder end for the current models, and yes, you can discount this on me being a good engineer, knowing my tools well, etc etc. but it surely felt to me that something new was unlocked with gpt-5.2 xhigh and codex. i found it to be an extremely rigorous model that follows instructions to the letter, and doesn’t invent stuff by itself. paired with gpt-5.2 pro for planning, it works extremely well.

i shipped two large and complex projects with it in a month. and honestly im amazed with the capabilities already. in the right hands these tools can give you amazing results. people focus on one shot wonders, but the real test is what you can achieve when you use these models for determined work. and with that im satisfied.

hope you learned something useful and will go and try to preserve a bright memory from your childhood. it will be a lot of work, but it will be worth it in the end.

## the invitation

if the original crimsonland is still in your muscle memory and you can call out subtle inconsistencies like “hmm i think this spider had friendly fire”, you can help speed up squashing the remaining bugs. our binary files are static, we will find all inconsistencies eventually anyway.

you can also join the [telegram group](https://t.me/+0lAIK7SFOWQ2YzQy) to follow the project.

if you want to study the code, check out the [github repo](https://github.com/banteg/crimson).

then you can look up how different mechanics work up to the implementation detail in the [knowledge base](https://crimson.banteg.xyz/).

if you just want to enjoy some action, you can play my version right now (you need [uv](https://docs.astral.sh/uv/getting-started/installation/) package manager).

```
uvx crimsonland@latest
```

p.s. the screenshot labeled crimsonland 2003 is actually from my version
