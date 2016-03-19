package com.hexgame;

import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.Batch;
import com.badlogic.gdx.graphics.g2d.Sprite;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Created by leheli on 2016.03.14..
 */
public class SpriteRow {

    public List<GameObject> list = new ArrayList<GameObject>();
    public Map<GridLocation,GameObject> grid= new HashMap<GridLocation, GameObject>();
   // public static final float scaleFactor = 0.5f;

    public SpriteRow(int nrOfHexes, Texture texture) {

        addRow(list,grid, texture, 4, 0, -3, Xrow0);
        addRow(list,grid, texture, 5, 1, -2, Xrow1);
        addRow(list,grid, texture, 6, 2, -1, Xrow2);
        addRow(list,grid, texture, 7, 3, 0, Xrow3);
        addRow(list,grid, texture, 6, 4, -1, Xrow4);
        addRow(list,grid, texture, 5, 5, -2, Xrow5);
        addRow(list, grid, texture, 4, 6, -3, Xrow6);

        GameObject start = list.get(0);
        start.setColor(Color.GREEN);
        GameObject end = list.get(list.size()-1);
        end.setColor(Color.GREEN);
    }


    private static void addRow(List<GameObject> list,Map<GridLocation,GameObject> grid,Texture texture, int nrOfHexes, int rowNum, int paddBy, int[] XRowCoordinates) {
        for (int i = 0; i < nrOfHexes; i++) {

            int gridX = XRowCoordinates[i];
            int gridZ = getZ(rowNum);
            int gridY = getOther(gridX, gridZ);

            GameObject sprite = new GameObject(texture, new GridLocation(gridX,gridY,gridZ));
            //sprite.scale(-0.5f);
            sprite.setY(rowNum * getRow2Y(sprite));
            sprite.setX(Math.abs(paddBy) * padding(sprite) + getNextX(i, sprite));
            list.add(sprite);
            grid.put(sprite.location,sprite);
        }
        System.out.println();

    }

    private static int getOther(int gridY, int gridZ) {
        return (-gridY) - gridZ;
    }

    private static int getZ(int nrInRow) {
        return 3 - nrInRow;
    }

    private static float getRow2Y(Sprite hex) {
        return getScaledHeight(hex) - 2 - getScaledHeight(hex) / 4;
    }

    private static float padding(Sprite hex) {
        return (getScaledWidth(hex) - 5) / 2;
    }

    private static float getNextX(int nr, Sprite hex) {
        return nr == 0 ? 0 : nr * (getScaledWidth(hex) - 5);
    }

    private static float getScaledWidth(Sprite hex) {
        return hex.getWidth();
    }

    private static float getScaledHeight(Sprite hex) {
        return hex.getHeight();
    }

    public void draw(Batch batch) {
        for (Sprite sprite : list) {
            sprite.draw(batch);
        }
    }

    public static final int[] Xrow0 = generateXRow(-3, 0);
    public static final int[] Xrow1 = generateXRow(-3, 1);
    public static final int[] Xrow2 = generateXRow(-3, 2);
    public static final int[] Xrow3 = generateXRow(-3, 3);
    public static final int[] Xrow4 = generateXRow(-2, 3);
    public static final int[] Xrow5 = generateXRow(-1, 3);
    public static final int[] Xrow6 = generateXRow(0, 3);

    public static int[] generateXRow(int from, int to) {
        int lenght = Math.abs(from) + Math.abs(to) + 1;
        int[] res = new int[lenght];
        for (int i = 0; i < lenght; i++) {
            res[i] = from + i;
        }
        return res;
    }


}
