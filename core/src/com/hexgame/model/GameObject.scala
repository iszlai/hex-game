package com.hexgame.model

import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.Sprite
import java.util

/**
  * Created by leheli on 2016.08.01..
  */
class GameObject extends Sprite {
  val location: GridLocation = null
  var grid: util.Map[GridLocation, GameObject] = null
  var clickable: Boolean = true
  var walkAble: Boolean = false

  def this(texture: Texture, location: GridLocation, grid: util.Map[GridLocation, GameObject]) {
    this()
    `super`(texture)
    this.location = location
    this.grid = grid
  }

  def getAvailableNeighbours: util.Set[GameObject] = {
    val res: util.Set[GameObject] = new util.HashSet[GameObject]
    for (side <- Sides.values) {
      val neighbour: GridLocation = location.getNeighbour(side)
      val gameObject: GameObject = grid.get(neighbour)
      if (gameObject != null && gameObject.walkAble) {
        res.add(gameObject)
      }
    }
    return res
  }

  override def equals(o: AnyRef): Boolean = {
    if (this eq o) return true
    if (o == null || getClass ne o.getClass) return false
    val that: GameObject = o.asInstanceOf[GameObject]
    if (clickable != that.clickable) return false
    return !(if (location != null) !(location == that.location) else that.location != null)
  }

  override def hashCode: Int = {
    var result: Int = if (location != null) location.hashCode else 0
    result = 31 * result + (if (clickable) 1 else 0)
    return result
  }
}