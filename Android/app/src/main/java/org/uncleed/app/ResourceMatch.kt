// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import java.text.Normalizer
import java.util.Locale
object ResourceMatch {
 fun title(name:String):String=name.replace(Regex("\\.(gba|gbc|gb|nds|iso|cso|3ds|cci|pbp|chd|cxi|3dsx)$",RegexOption.IGNORE_CASE),"").replace(Regex("\\s*\\([^)]*\\)|\\s*\\[[^]]*]"),"").trim().replace(", The","",true).let{if(name.contains(", The",true))"The $it" else it}.replace(" - ",": ")
 fun normalized(name:String)=Normalizer.normalize(title(name),Normalizer.Form.NFD).replace(Regex("\\p{M}+"),"").lowercase(Locale.ROOT).split(Regex("[^\\p{L}\\p{N}]+" )).filter{it.isNotEmpty()&&it!="the"&&it!="version"}.joinToString("")
 private fun regions(name:String):List<String>{val groups=Regex("\\([^)]*\\)|\\[[^]]*]").findAll(name).map{it.value}.joinToString(" ");return listOf("USA","Europe","Japan","Australia","World").filter{Regex("\\b$it\\b",RegexOption.IGNORE_CASE).containsMatchIn(groups)}}
 fun region(name:String)=regions(name).firstOrNull()
 fun variant(name:String)=listOf("demo","kiosk","beta","proto","dpad").filter{name.lowercase(Locale.ROOT).contains("($it")}.joinToString("-")
 fun key(game:Game)=game.machine.key+":"+normalized(game.originalName)+":"+(region(game.originalName)?.takeUnless{it=="World"}?:"first-release")+":"+variant(game.originalName)
 fun cover(name:String,candidates:List<String>):String? {
  candidates.firstOrNull{it.equals(name.substringBeforeLast('.'),true)}?.let{return it}
  val matches=candidates.filter{normalized(it)==normalized(name)&&variant(it)==variant(name)}
  val region=region(name)
  return if(region!=null)matches.firstOrNull{region in regions(it)} else matches.singleOrNull()
 }
 fun identity(name:String):String {val t=title(name);return mapOf("pokemonfirered" to "Pokémon FireRed and LeafGreen","pokemonleafgreen" to "Pokémon FireRed and LeafGreen","pokemongold" to "Pokémon Gold and Silver","pokemonsilver" to "Pokémon Gold and Silver","pokemonblack" to "Pokémon Black and White","pokemonwhite" to "Pokémon Black and White","pokemonheartgold" to "Pokémon HeartGold and SoulSilver")[normalized(t)]?:t}
}
