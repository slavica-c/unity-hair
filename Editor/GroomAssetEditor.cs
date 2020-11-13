﻿using UnityEngine;
using UnityEditor;

namespace Unity.DemoTeam.Hair
{
	using static HairGUI;

	[CustomEditor(typeof(GroomAsset))]
	public class GroomAssetEditor : Editor
	{
		static Material s_previewMat;

		PreviewRenderUtility previewUtil;
		MaterialPropertyBlock previewUtilMPB;
		Quaternion previewRotation;

		SerializedProperty _settingsBasic;
		SerializedProperty _settingsBasic_type;
		SerializedProperty _settingsBasic_material;
		SerializedProperty _settingsAlembic;
		SerializedProperty _settingsProcedural;

		SerializedProperty _strandGroups;
		SerializedProperty _strandGroupsAutoBuild;

		void OnEnable()
		{
			if (previewUtil != null)
				previewUtil.Cleanup();

			previewUtil = new PreviewRenderUtility();
			previewUtilMPB = new MaterialPropertyBlock();
			previewRotation = Quaternion.identity;

			previewUtil.camera.backgroundColor = Color.black;// Color.Lerp(Color.black, Color.grey, 0.5f);
			previewUtil.camera.nearClipPlane = 0.001f;
			previewUtil.camera.farClipPlane = 50.0f;
			previewUtil.camera.fieldOfView = 90.0f;
			previewUtil.camera.transform.position = Vector3.zero;
			previewUtil.camera.transform.LookAt(Vector3.forward, Vector3.up);

			previewUtil.lights[0].transform.position = Vector3.zero + Vector3.up;
			previewUtil.lights[0].intensity = 5.0f;

			for (int i = 1; i != previewUtil.lights.Length; i++)
			{
				previewUtil.lights[i].enabled = false;
			}

			_settingsBasic = serializedObject.FindProperty("settingsBasic");
			_settingsBasic_type = _settingsBasic.FindPropertyRelative("type");
			_settingsBasic_material = _settingsBasic.FindPropertyRelative("material");
			_settingsAlembic = serializedObject.FindProperty("settingsAlembic");
			_settingsProcedural = serializedObject.FindProperty("settingsProcedural");

			_strandGroups = serializedObject.FindProperty("strandGroups");
			_strandGroupsAutoBuild = serializedObject.FindProperty("strandGroupsAutoBuild");
		}

		void OnDisable()
		{
			previewUtil.Cleanup();
		}

		public override void OnInspectorGUI()
		{
			var groom = target as GroomAsset;
			if (groom == null)
				return;

			EditorGUILayout.LabelField("Importer", EditorStyles.centeredGreyMiniLabel);
			EditorGUILayout.BeginVertical(HairGUI.settingsBox);
			{
				DrawImporterGUI();
			}
			EditorGUILayout.EndVertical();

			EditorGUILayout.Space();
			EditorGUILayout.LabelField("Strand groups", EditorStyles.centeredGreyMiniLabel);
			EditorGUILayout.BeginVertical(HairGUI.settingsBox);
			{
				DrawStrandGroupsGUI();
			}
			EditorGUILayout.EndVertical();

			EditorGUILayout.Space();
			EditorGUILayout.LabelField(groom.checksum, EditorStyles.centeredGreyMiniLabel);
		}

		public void DrawImporterGUI()
		{
			var groom = target as GroomAsset;
			if (groom == null)
				return;

			EditorGUI.BeginChangeCheck();
			{
				StructPropertyFieldsWithHeader(_settingsBasic);

				if (_settingsBasic_material.objectReferenceValue == null)
					_settingsBasic_material.objectReferenceValue = groom.defaultMaterial;

				EditorGUILayout.Space();

				switch ((GroomAsset.Type)_settingsBasic_type.enumValueIndex)
				{
					case GroomAsset.Type.Alembic:
						StructPropertyFieldsWithHeader(_settingsAlembic);
						break;
					case GroomAsset.Type.Procedural:
						StructPropertyFieldsWithHeader(_settingsProcedural);
						break;
				}
			}

			bool settingsChanged = EditorGUI.EndChangeCheck();

			EditorGUILayout.Space();
			EditorGUILayout.BeginHorizontal();
			{
				if (GUILayout.Button("Build strand groups") || (settingsChanged && _strandGroupsAutoBuild.boolValue))
				{
					GroomAssetBuilder.ClearGroomAsset(groom);
					serializedObject.ApplyModifiedPropertiesWithoutUndo();
					GroomAssetBuilder.BuildGroomAsset(groom);
					serializedObject.Update();
				}

				_strandGroupsAutoBuild.boolValue = EditorGUILayout.ToggleLeft("Auto", _strandGroupsAutoBuild.boolValue, GUILayout.Width(50.0f));
			}
			EditorGUILayout.EndHorizontal();
		}

		public void DrawStrandGroupsGUI()
		{
			var groom = target as GroomAsset;
			if (groom == null)
				return;

			if (groom.strandGroups == null || groom.strandGroups.Length == 0)
			{
				EditorGUILayout.LabelField("None");
			}
			else
			{
				int numStrands = 0;
				int numParticles = 0;

				for (int i = 0; i != groom.strandGroups.Length; i++)
				{
					numStrands += groom.strandGroups[i].strandCount;
					numParticles += groom.strandGroups[i].strandCount * groom.strandGroups[i].strandParticleCount;
				}

				EditorGUILayout.LabelField("Summary", EditorStyles.miniBoldLabel);
				using (new EditorGUI.IndentLevelScope())
				{
					EditorGUILayout.IntField("Total groups", groom.strandGroups.Length, EditorStyles.label);
					EditorGUILayout.IntField("Total strands", numStrands, EditorStyles.label);
					EditorGUILayout.IntField("Total particles", numParticles, EditorStyles.label);
				}

				for (int i = 0; i != groom.strandGroups.Length; i++)
				{
					EditorGUILayout.Space();
					EditorGUILayout.LabelField("Group:" + i, EditorStyles.miniBoldLabel);
					using (new EditorGUI.IndentLevelScope())
					{
						EditorGUILayout.BeginVertical();
						{
							var meshRoots = groom.strandGroups[i].meshAssetRoots;
							var meshLines = groom.strandGroups[i].meshAssetLines;
							var meshCenter = meshLines.bounds.center;
							var meshRadius = meshLines.bounds.extents.magnitude;
							var meshOffset = Mathf.Sqrt(2.0f * meshRadius * meshRadius);

							var rect = GUILayoutUtility.GetRect(150.0f, 150.0f);
							if (rect.width >= 200.0f)
							{
								rect = EditorGUI.IndentedRect(rect);

								GUI.Box(rect, Texture2D.blackTexture, EditorStyles.textField);

								rect.xMin += 1;
								rect.yMin += 1;
								rect.xMax -= 1;
								rect.yMax -= 1;

								//if (rect.Contains(Event.current.mousePosition))
								//{
								//	float fracX = (Event.current.mousePosition.x - rect.x) / rect.width;
								//	float fracY = (Event.current.mousePosition.y - rect.y) / rect.height;
								//	{
								//		previewRotation = Quaternion.Euler(0.0f, 360.0f * fracX, 0.0f);
								//	}
								//	EditorUtility.SetDirty(groom);
								//}

								//var editor = Editor.CreateEditor(meshLines);
								//editor.OnPreviewGUI(rect, GUIStyle.none);
								//DestroyImmediate(editor);

								var matrix = Matrix4x4.TRS(meshOffset * Vector3.forward, previewRotation, Vector3.one) * Matrix4x4.Translate(-meshCenter);

								var material = _settingsBasic_material.objectReferenceValue as Material;
								if (material == null)
									material = groom.defaultMaterial;

								previewUtilMPB.SetInt("_StrandCount", groom.strandGroups[i].strandCount);

								previewUtil.BeginPreview(rect, GUIStyle.none);
								previewUtil.DrawMesh(meshLines, matrix, material, 0, previewUtilMPB);
								previewUtil.Render(true, true);
								previewUtil.EndAndDrawPreview(rect);
							}
						}
						EditorGUILayout.EndVertical();

						using (new EditorGUI.DisabledScope(true))
						{
							StructPropertyFields(_strandGroups.GetArrayElementAtIndex(i));
						}
					}
				}

				EditorGUILayout.Space();
				using (new EditorGUI.DisabledScope(true))
				{
					if (GUILayout.Button("Save changes"))
					{
						// TODO
					}
				}
			}
		}
	}
}
