// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import org.junit.Assert.*
import org.junit.Test
class ResourceMatchTests {
 @Test fun matchesAccentsAndOriginalRegion(){assertEquals("Pokémon - FireRed Version (USA)",ResourceMatch.cover("Pokemon - FireRed Version (USA).gba",listOf("Pokémon - FireRed Version (Europe)","Pokémon - FireRed Version (USA)")))}
 @Test fun neverSubstitutesOtherRegion(){assertNull(ResourceMatch.cover("Example (Japan).gba",listOf("Example (USA)")))}
 @Test fun demoDoesNotMatchRetail(){assertNull(ResourceMatch.cover("Example (USA) (Demo).gba",listOf("Example (USA)")))}
 @Test fun missingRegionDoesNotGuessAmbiguousEdition(){assertNull(ResourceMatch.cover("Example.gba",listOf("Example (USA)","Example (Europe)")))}
 @Test fun punctuationInsidePlainTitlesSurvives(){assertEquals(ResourceMatch.normalized("Mario vs. Donkey Kong"),ResourceMatch.normalized("Mario vs. Donkey Kong (USA).gba"))}
 @Test fun articleAndPlatformIdentity(){val g=Game("id",Machine.GBA,"","hash.gba","Legend of Zelda, The - A Link to the Past & Four Swords (USA).gba");assertTrue(ResourceMatch.key(g).startsWith("gba:legendofzeldaalinktopastfourswords:USA:"))}
}
