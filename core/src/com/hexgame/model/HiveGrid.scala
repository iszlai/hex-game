package com.hexgame.model

import com.badlogic.gdx.graphics.g2d.{Sprite, Batch}
import com.badlogic.gdx.graphics.{Texture, Color}
import java.util

import com.hexgame.helper.HexHelper

/**
  * Created by leheli on 2016.08.01..
  */
class HiveGrid(nrOfHexes: Int, texture: Texture, nrOfObstacles: Int) {
  var list: util.List[GameObject] = new util.ArrayList[GameObject]
  var grid: util.Map[GridLocation, GameObject] = new util.HashMap[GridLocation, GameObject]
  var start: GameObject = null
  var end: GameObject = null
  init()
  def init() {

    addRow(list, grid, texture, 4, 0, -3, Xrow0)
    addRow(list, grid, texture, 5, 1, -2, Xrow1)
    addRow(list, grid, texture, 6, 2, -1, Xrow2)
    addRow(list, grid, texture, 7, 3, 0, Xrow3)
    addRow(list, grid, texture, 6, 4, -1, Xrow4)
    addRow(list, grid, texture, 5, 5, -2, Xrow5)
    addRow(list, grid, texture, 4, 6, -3, Xrow6)
    start = list.get(0)
    start.setColor(Color.GREEN)
    start.walkAble = true
    end = list.get(list.size - 1)
    end.setColor(Color.GREEN)
    end.walkAble = true
    blockElements(HexHelper.getElementsToBlock(list, nrOfObstacles))
  }

  private def blockElements(elementsToBlock: util.List[GameObject]) {
    import scala.collection.JavaConversions._
    for (e <- elementsToBlock) {
      e.setColor(Color.BLACK)
      e.clickable = false
    }
  }

  private def addRow(list: util.List[GameObject], grid: util.Map[GridLocation, GameObject], texture: Texture, nrOfHexes: Int, rowNum: Int, paddBy: Int, XRowCoordinates: Array[Int]) {
    {
      var i: Int = 0
      while (i < nrOfHexes) {
        {
          val gridX: Int = XRowCoordinates(i)
          val gridZ: Int = getZ(rowNum)
          val gridY: Int = getOther(gridX, gridZ)
          val sprite: GameObject = new GameObject(texture, new GridLocation(gridX, gridY, gridZ), grid)
          sprite.setY(rowNum * getRow2Y(sprite))
          sprite.setX(Math.abs(paddBy) * padding(sprite) + getNextX(i, sprite))
          list.add(sprite)
          grid.put(sprite.location, sprite)
        }
        ({
          i += 1; i - 1
        })
      }
    }
    System.out.println
  }

  private def getOther(gridY: Int, gridZ: Int): Int = {
    return (-gridY) - gridZ
  }

  private def getZ(nrInRow: Int): Int = {
    return 3 - nrInRow
  }

  private def getRow2Y(hex: Sprite): Float = {
    return getScaledHeight(hex) - 2 - getScaledHeight(hex) / 4
  }

  private def padding(hex: Sprite): Float = {
    return (getScaledWidth(hex) - 5) / 2
  }

  private def getNextX(nr: Int, hex: Sprite): Float = {
    return if (nr == 0) 0 else nr * (getScaledWidth(hex) - 5)
  }

  private def getScaledWidth(hex: Sprite): Float = {
    return hex.getWidth
  }

  private def getScaledHeight(hex: Sprite): Float = {
    return hex.getHeight
  }

  def draw(batch: Batch) {
    import scala.collection.JavaConversions._
    for (sprite <- list) {
      sprite.draw(batch)
    }
  }

  val Xrow0: Array[Int] = generateXRow(-3, 0)
  val Xrow1: Array[Int] = generateXRow(-3, 1)
  val Xrow2: Array[Int] = generateXRow(-3, 2)
  val Xrow3: Array[Int] = generateXRow(-3, 3)
  val Xrow4: Array[Int] = generateXRow(-2, 3)
  val Xrow5: Array[Int] = generateXRow(-1, 3)
  val Xrow6: Array[Int] = generateXRow(0, 3)

  def generateXRow(from: Int, to: Int): Array[Int] = {
    val lenght: Int = Math.abs(from) + Math.abs(to) + 1
    val res = for (i <- 0 to lenght) yield from + i
    res.toArray

  }
}