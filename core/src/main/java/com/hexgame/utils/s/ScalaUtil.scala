package com.hexgame.utils.s

import java.security.SecureRandom
import java.util
import java.util.Random

/**
  * Created by leheli on 2016.07.31..
  */
object ScalaUtil {
  private val RANDOM: Random = new SecureRandom

   def randomListNrOfElements(to: Int, howMany: Int): util.Set[Integer] = {
    val res: util.Set[Integer] = new util.HashSet[Integer]
    while (res.size < howMany) {
      res.add(1 + RANDOM.nextInt(to))
    }
    return res
  }

}
