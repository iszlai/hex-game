package com.hexgame.utils.s

import java.security.SecureRandom
import java.util.Random

/**
  * Created by leheli on 2016.08.01..
  */
class Utils {
  private val RANDOM: Random = new SecureRandom

  def randomEnum[T <: Enum[(_$1) forSome {type _$1}]](clazz: Class[T]): T = {
    val x: Int = RANDOM.nextInt(clazz.getEnumConstants.length)
    return clazz.getEnumConstants(x)
  }

  def randomListNrOfElements(to: Int, howMany: Int): util.Set[Integer] = {
    val res: util.Set[Integer] = new util.HashSet[Integer]
    while (res.size < howMany) {
      res.add(1 + RANDOM.nextInt(to))
    }
    return res
  }

  private def getSubset(ids: util.Set[Integer], list: util.List[GameObject]): util.List[GameObject] = {
    val res: util.List[GameObject] = new util.ArrayList[GameObject]
    import scala.collection.JavaConversions._
    for (i <- ids) {
      res.add(list.get(i))
    }
    return res
  }

  def getElementsToBlock(list: util.List[GameObject], howMany: Int): util.List[GameObject] = {
    val ids: util.Set[Integer] = randomListNrOfElements(list.size - 1, howMany)
    return getSubset(ids, list)
  }

  def isGameOver(current: GameObject, end: GameObject): Boolean = {
    return isGameOver(current, end, new util.HashSet[GameObject], new util.LinkedList[GameObject])
  }

  private def isGameOver(current: GameObject, end: GameObject, traversed: util.Set[GameObject], frontier: util.Queue[GameObject]): Boolean = {
    if (current.location == end.location) {
      return true
    }
    val availableNeighbours: util.Set[GameObject] = current.getAvailableNeighbours
    import scala.collection.JavaConversions._
    for (neighbour <- availableNeighbours) {
      if (!traversed.contains(neighbour)) {
        frontier.add(neighbour)
      }
    }
    if (frontier.isEmpty) {
      return false
    }
    traversed.add(current)
    val toVisit: GameObject = frontier.remove
    return isGameOver(toVisit, end, traversed, frontier)
  }
}