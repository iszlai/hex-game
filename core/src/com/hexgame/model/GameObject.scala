package com.hexgame.model

import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.Sprite
import java.util

/**
  * Created by leheli on 2016.08.01..
  */
class GameObject(texture: Texture,val location: GridLocation, grid: util.Map[GridLocation, GameObject]) extends Sprite(texture) {

  var clickable: Boolean = true
  var walkAble: Boolean = false


  def getAvailableNeighbours: util.Set[GameObject] = {
    val res: util.Set[GameObject] = new util.HashSet[GameObject]
    for (side <- Side.sides) {
      val neighbour: GridLocation = location.getNeighbour(side)
      val gameObject: GameObject = grid.get(neighbour)
      if (gameObject != null && gameObject.walkAble) {
        res.add(gameObject)
      }
    }
    return res
  }


}